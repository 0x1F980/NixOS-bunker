//! Minimal ratatui UI: CRUD AppVMs / Disposables in zones.json (not Nix modules).
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph},
    Frame, Terminal,
};
use serde_json::{json, Map, Value};
use std::{
    env, fs,
    io::{self, Stdout},
    path::PathBuf,
    process::Command,
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Screen {
    List,
    Edit,
    Help,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum InputKind {
    None,
    AddName,
    AddIsoName,
    AddIsoPath,
    AddApp,
    AddUsb,
    SetIso,
    SetMem,
    SetVcpu,
    Rename,
    ConfirmDelete,
}

const TEMPLATES: &[&str] = &["desktop", "dev", "browser", "radio", "iso"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];
const MEM_STEPS: &[u64] = &[
    512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384,
];
const VCPU_STEPS: &[u64] = &[1, 2, 4, 6, 8, 12, 16];
const KINDS: &[&str] = &["appvm", "disposable", "template"];
const BOOT_MODES: &[&str] = &["iso", "disk", "both"];

struct App {
    zones_path: PathBuf,
    zones: Map<String, Value>,
    screen: Screen,
    zone_names: Vec<String>,
    list: ListState,
    status: String,
    dirty: bool,
    input: String,
    input_kind: InputKind,
    /// Name held while prompting for ISO path (`AddIsoPath`).
    pending_name: String,
}

fn zone_kind(z: &Value) -> &str {
    match z.get("kind").and_then(|x| x.as_str()) {
        Some("template") => "template",
        Some("disposable") => "disposable",
        Some("appvm") => "appvm",
        _ if z.get("disposable").and_then(|x| x.as_bool()) == Some(true) => "disposable",
        _ => "appvm",
    }
}

fn is_iso_zone(z: &Value) -> bool {
    z.get("template").and_then(|x| x.as_str()) == Some("iso")
        || z
            .get("iso")
            .and_then(|x| x.as_str())
            .map(|s| !s.is_empty())
            .unwrap_or(false)
}


fn color_hex(name: &str) -> &'static str {
    match name {
        "red" => "#cc0000",
        "orange" => "#f57900",
        "yellow" => "#edd400",
        "green" => "#73d216",
        "blue" => "#3465a4",
        "purple" => "#75507b",
        "black" => "#2e3436",
        "gray" => "#888a85",
        _ => "#888a85",
    }
}

fn iso_label(z: &Value) -> String {
    z.get("iso")
        .and_then(|x| x.as_str())
        .map(|p| {
            PathBuf::from(p)
                .file_name()
                .map(|f| f.to_string_lossy().into_owned())
                .unwrap_or_else(|| p.to_string())
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "—".into())
}

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let raw = fs::read_to_string(&path)?;
        let v: Value = serde_json::from_str(&raw)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let zones = v.as_object().cloned().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidData, "zones.json root must be object")
        })?;
        let mut zone_names: Vec<String> = zones.keys().cloned().collect();
        zone_names.sort();
        let mut list = ListState::default();
        if !zone_names.is_empty() {
            list.select(Some(0));
        }
        Ok(Self {
            zones_path: path,
            zones,
            screen: Screen::List,
            zone_names,
            list,
            status: "CRUD AppVM / Disposable / Template / ISO-HVM — same zones.json.".into(),
            dirty: false,
            input: String::new(),
            input_kind: InputKind::None,
            pending_name: String::new(),
        })
    }

    fn refresh_names(&mut self) {
        let sel = self.selected_zone().map(|s| s.to_string());
        self.zone_names = self.zones.keys().cloned().collect();
        self.zone_names.sort();
        if let Some(name) = sel {
            if let Some(i) = self.zone_names.iter().position(|n| n == &name) {
                self.list.select(Some(i));
                return;
            }
        }
        if self.zone_names.is_empty() {
            self.list.select(None);
        } else {
            self.list
                .select(Some(self.list.selected().unwrap_or(0).min(self.zone_names.len() - 1)));
        }
    }

    fn selected_zone(&self) -> Option<&str> {
        self.list.selected().map(|i| self.zone_names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let v = Value::Object(self.zones.clone());
        let pretty = serde_json::to_string_pretty(&v)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.zones_path.with_extension("json.bak");
        let _ = fs::copy(&self.zones_path, &bak);
        fs::write(&self.zones_path, pretty + "\n")?;
        self.dirty = false;
        let any_iso = self.zones.values().any(is_iso_zone);
        self.status = if any_iso {
            format!(
                "Saved {}. ISO zones: start now. NixOS guests: sudo nixos-rebuild switch --flake .#host",
                self.zones_path.display()
            )
        } else {
            format!(
                "Saved {}. Then: sudo nixos-rebuild switch --flake .#host",
                self.zones_path.display()
            )
        };
        Ok(())
    }

    fn next_free(&self) -> (String, String, u64) {
        let mut used_ip = std::collections::HashSet::new();
        let mut used_socks = std::collections::HashSet::new();
        let mut used_mac = std::collections::HashSet::new();
        for z in self.zones.values() {
            if let Some(ip) = z.get("ip").and_then(|x| x.as_str()) {
                if let Some(last) = ip.rsplit('.').next() {
                    if let Ok(n) = last.parse::<u8>() {
                        used_ip.insert(n);
                    }
                }
            }
            if let Some(s) = z.get("socks").and_then(|x| x.as_u64()) {
                used_socks.insert(s);
            }
            if let Some(mac) = z.get("mac").and_then(|x| x.as_str()) {
                if let Some(last) = mac.rsplit(':').next() {
                    if let Ok(n) = u8::from_str_radix(last, 16) {
                        used_mac.insert(n);
                    }
                }
            }
        }
        let ipn = (11u8..250).find(|i| !used_ip.contains(i)).unwrap_or(200);
        let socks = (1081u64..1200).find(|p| !used_socks.contains(p)).unwrap_or(1199);
        let macn = (0x11u8..0xfe).find(|i| !used_mac.contains(i)).unwrap_or(0xaa);
        (
            format!("10.0.0.{ipn}"),
            format!("02:b0:00:00:00:{macn:02x}"),
            socks,
        )
    }

    fn add_zone(&mut self, name: &str) {
        let name = name.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name must be alphanumeric / _ / -".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("Zone exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "template": "browser",
                "kind": "appvm",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 1536,
                "vcpu": 2,
                "disposable": false,
                "color": "red",
                "internet": "nym",
                "usb": [],
                "apps": [],
                "voice": false,
                "metadata": false
            }),
        );
        self.refresh_names();
        if let Some(i) = self.zone_names.iter().position(|n| n == name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!("Added {name} (NixOS) — t/c/i/k/m, then w save + rebuild");
    }

    fn add_iso_zone(&mut self, name: &str, iso_path: &str) {
        let name = name.trim();
        let iso_path = iso_path.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name must be alphanumeric / _ / -".into();
            return;
        }
        if iso_path.is_empty() {
            self.status = "Need absolute path to .iso / .img".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("Zone exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "template": "iso",
                "iso": iso_path,
                "boot": "iso",
                "display": "gtk",
                "diskGb": 16,
                "kind": "disposable",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 2048,
                "vcpu": 2,
                "disposable": true,
                "color": "purple",
                "internet": "none",
                "usb": [],
                "apps": [],
                "voice": false,
                "metadata": false
            }),
        );
        self.refresh_names();
        if let Some(i) = self.zone_names.iter().position(|n| n == name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!(
            "Added ISO/HVM {name} (disposable) — k=kind  b=boot  o=path  w save  s start"
        );
    }

    fn delete_selected(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        self.zones.remove(&name);
        self.refresh_names();
        self.dirty = true;
        self.screen = Screen::List;
        self.status = format!("Removed {name} (unsaved until w)");
    }

    fn rename_zone(&mut self, new_name: &str) {
        let new_name = new_name.trim();
        let Some(old) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        if new_name.is_empty()
            || !new_name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name must be alphanumeric / _ / -".into();
            return;
        }
        if new_name == old {
            self.status = "Name unchanged".into();
            return;
        }
        if self.zones.contains_key(new_name) {
            self.status = format!("Zone exists: {new_name}");
            return;
        }
        let Some(val) = self.zones.remove(&old) else {
            return;
        };
        self.zones.insert(new_name.into(), val);
        self.refresh_names();
        if let Some(i) = self.zone_names.iter().position(|n| n == new_name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.status = format!(
            "Renamed {old} → {new_name}  (save + nixos-rebuild for icons/cursor)"
        );
    }

    fn zone_obj_mut(&mut self) -> Option<&mut Map<String, Value>> {
        let name = self.selected_zone()?.to_string();
        self.zones.get_mut(&name)?.as_object_mut()
    }

    fn cycle_str_field(&mut self, key: &str, options: &[&str]) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj.get(key).and_then(|x| x.as_str()).unwrap_or(options[0]);
        let idx = options.iter().position(|m| *m == cur).unwrap_or(0);
        let next = options[(idx + 1) % options.len()];
        obj.insert(key.into(), json!(next));
        self.dirty = true;
        if key == "color" {
            self.status = format!(
                "color → {next} {}  (host icons + NixOS cursor after rebuild)",
                color_hex(next)
            );
        } else {
            self.status = format!("{key} → {next}");
        }
    }

    fn toggle_kind(&mut self) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj
            .get("kind")
            .and_then(|x| x.as_str())
            .unwrap_or_else(|| {
                if obj.get("disposable").and_then(|x| x.as_bool()) == Some(true) {
                    "disposable"
                } else {
                    "appvm"
                }
            });
        let idx = KINDS.iter().position(|k| *k == cur).unwrap_or(0);
        let next = KINDS[(idx + 1) % KINDS.len()];
        obj.insert("kind".into(), json!(next));
        obj.insert("disposable".into(), json!(next == "disposable"));
        self.dirty = true;
        self.status = format!("kind → {next}");
    }

    fn set_iso_path(&mut self, path: &str) {
        let path = path.trim();
        if path.is_empty() {
            self.status = "Need absolute path to .iso / .img".into();
            return;
        }
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        obj.insert("template".into(), json!("iso"));
        obj.insert("iso".into(), json!(path));
        if obj.get("boot").is_none() {
            obj.insert("boot".into(), json!("iso"));
        }
        if obj.get("display").is_none() {
            obj.insert("display".into(), json!("gtk"));
        }
        if obj.get("diskGb").is_none() {
            obj.insert("diskGb".into(), json!(16));
        }
        self.dirty = true;
        self.status = format!("iso → {path} (template=iso)");
    }

    fn cycle_boot(&mut self) {
        if !self
            .selected_zone()
            .and_then(|n| self.zones.get(n))
            .map(is_iso_zone)
            .unwrap_or(false)
        {
            self.status = "boot only applies to ISO/HVM zones (template=iso)".into();
            return;
        }
        self.cycle_str_field("boot", BOOT_MODES);
    }

    fn cycle_mem(&mut self, up: bool) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj.get("mem").and_then(|x| x.as_u64()).unwrap_or(1536);
        let idx = MEM_STEPS
            .iter()
            .position(|m| *m == cur)
            .unwrap_or_else(|| {
                MEM_STEPS
                    .iter()
                    .position(|m| *m > cur)
                    .unwrap_or(MEM_STEPS.len().saturating_sub(1))
            });
        let next = if up {
            MEM_STEPS[(idx + 1) % MEM_STEPS.len()]
        } else {
            MEM_STEPS[(idx + MEM_STEPS.len() - 1) % MEM_STEPS.len()]
        };
        obj.insert("mem".into(), json!(next));
        self.dirty = true;
        self.status = format!("RAM mem → {next} MiB  (m/M step, r = type exact)");
    }

    fn cycle_vcpu(&mut self, up: bool) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let cur = obj.get("vcpu").and_then(|x| x.as_u64()).unwrap_or(2);
        let idx = VCPU_STEPS
            .iter()
            .position(|m| *m == cur)
            .unwrap_or_else(|| {
                VCPU_STEPS
                    .iter()
                    .position(|m| *m > cur)
                    .unwrap_or(VCPU_STEPS.len().saturating_sub(1))
            });
        let next = if up {
            VCPU_STEPS[(idx + 1) % VCPU_STEPS.len()]
        } else {
            VCPU_STEPS[(idx + VCPU_STEPS.len() - 1) % VCPU_STEPS.len()]
        };
        obj.insert("vcpu".into(), json!(next));
        self.dirty = true;
        self.status = format!("vCPU → {next}  (v/V step, N = type exact)");
    }

    fn set_mem_mib(&mut self, raw: &str) {
        let s = raw.trim().to_lowercase().replace('m', "").replace("ib", "");
        let Ok(n) = s.parse::<u64>() else {
            self.status = "RAM: enter MiB number, e.g. 4096".into();
            return;
        };
        if !(256..=65536).contains(&n) {
            self.status = "RAM must be 256..65536 MiB".into();
            return;
        }
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        obj.insert("mem".into(), json!(n));
        self.dirty = true;
        self.status = format!("RAM mem → {n} MiB");
    }

    fn set_vcpu_n(&mut self, raw: &str) {
        let Ok(n) = raw.trim().parse::<u64>() else {
            self.status = "vCPU: enter integer 1..64".into();
            return;
        };
        if !(1..=64).contains(&n) {
            self.status = "vCPU must be 1..64".into();
            return;
        }
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        obj.insert("vcpu".into(), json!(n));
        self.dirty = true;
        self.status = format!("vCPU → {n}");
    }

    fn push_list(&mut self, field: &str, item: &str) {
        let item = item.trim();
        if item.is_empty() {
            return;
        }
        if field == "usb" {
            let ok = item.contains(':')
                && item.len() >= 5
                && item.chars().all(|c| c.is_ascii_hexdigit() || c == ':');
            if !ok {
                self.status = "Need vid:pid hex, e.g. 0bda:2838".into();
                return;
            }
        }
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let arr = obj.entry(field.to_string()).or_insert_with(|| json!([]));
        let list = arr.as_array_mut().unwrap();
        let val = if field == "usb" {
            json!(item.to_lowercase())
        } else {
            json!(item)
        };
        if !list.contains(&val) {
            list.push(val);
        }
        self.dirty = true;
        self.status = format!("added {field}: {item}");
    }

    fn pop_list(&mut self, field: &str) {
        let Some(obj) = self.zone_obj_mut() else {
            return;
        };
        let Some(arr) = obj.get_mut(field).and_then(|x| x.as_array_mut()) else {
            self.status = format!("{field} empty");
            return;
        };
        if arr.is_empty() {
            self.status = format!("{field} empty");
            return;
        }
        let removed = arr.pop();
        self.dirty = true;
        self.status = format!(
            "removed {field}: {}",
            removed
                .and_then(|v| v.as_str().map(|s| s.to_string()))
                .unwrap_or_default()
        );
    }

    fn start_selected(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        if self.dirty {
            self.status = "Save first (w) — unsaved changes".into();
            return;
        }
        self.status = format!("Starting {name}…");
        let _ = Command::new("bunker-zone-start").arg(&name).status();
        self.status = format!("bunker-zone-start {name}");
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(f.area());

    let title = match app.screen {
        Screen::List => "Bunker zones — AppVM · Disposable · Template · ISO/HVM",
        Screen::Edit => "Edit zone (NixOS template or ISO — same CRUD)",
        Screen::Help => "Help",
    };
    let dirty = if app.dirty { "  [UNSAVED]" } else { "" };
    f.render_widget(
        Paragraph::new(format!("{title}{dirty}"))
            .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            .block(Block::default().borders(Borders::ALL)),
        chunks[0],
    );

    match app.screen {
        Screen::List => draw_list(f, chunks[1], app),
        Screen::Edit => draw_edit(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }

    let hint = match app.input_kind {
        InputKind::AddName => format!("NixOS zone name> {}_   Enter=create  Esc=cancel", app.input),
        InputKind::AddIsoName => {
            format!("ISO/HVM zone name> {}_   Enter=next  Esc=cancel", app.input)
        }
        InputKind::AddIsoPath => format!(
            "ISO path for '{}'> {}_   Enter=create  Esc=cancel",
            app.pending_name, app.input
        ),
        InputKind::AddApp => format!("pkg name> {}_   Enter=add  Esc=cancel", app.input),
        InputKind::AddUsb => format!("vid:pid> {}_   Enter=add  Esc=cancel", app.input),
        InputKind::SetIso => format!("ISO path> {}_   Enter=set  Esc=cancel", app.input),
        InputKind::SetMem => format!("RAM MiB> {}_   Enter=set  Esc=cancel", app.input),
        InputKind::SetVcpu => format!("vCPU count> {}_   Enter=set  Esc=cancel", app.input),
        InputKind::Rename => format!("rename to> {}_   Enter=rename  Esc=cancel", app.input),
        InputKind::ConfirmDelete => "Delete zone?  y=yes  Esc/n=cancel".into(),
        InputKind::None => match app.screen {
            Screen::List => {
                "↑↓  Enter=edit  a=NixOS  A=ISO  c=color  n=rename  m/M=RAM  s=start  w=save  ?"
                    .into()
            }
            Screen::Edit => {
                "n=rename  c=color  m/M=RAM  v/V=CPU  t/o/i/k  u=usb  w=save  Esc".into()
            }
            Screen::Help => "Esc=back".into(),
        },
    };
    f.render_widget(
        Paragraph::new(Line::from(vec![
            Span::raw(hint),
            Span::raw("  |  "),
            Span::styled(&app.status, Style::default().fg(Color::Yellow)),
        ]))
        .block(Block::default().borders(Borders::ALL).title("keys")),
        chunks[2],
    );

    if matches!(
        app.input_kind,
        InputKind::AddName
            | InputKind::AddIsoName
            | InputKind::AddIsoPath
            | InputKind::AddApp
            | InputKind::AddUsb
            | InputKind::SetIso
            | InputKind::SetMem
            | InputKind::SetVcpu
            | InputKind::Rename
    ) {
        let area = centered(chunks[1], 72, 5);
        f.render_widget(Clear, area);
        let title = match app.input_kind {
            InputKind::AddName => "new NixOS zone name",
            InputKind::AddIsoName => "new ISO/HVM zone name (Tails, …)",
            InputKind::AddIsoPath => "absolute path to .iso / .img",
            InputKind::AddApp => "nixpkgs attr (apps) — NixOS only",
            InputKind::AddUsb => "usb vid:pid",
            InputKind::SetIso => "path to .iso / .img",
            InputKind::SetMem => "RAM in MiB (e.g. 4096)",
            InputKind::SetVcpu => "vCPU count (e.g. 4)",
            InputKind::Rename => "new zone name",
            _ => "input",
        };
        f.render_widget(
            Paragraph::new(app.input.as_str())
                .block(Block::default().borders(Borders::ALL).title(title)),
            area,
        );
    }
}

fn draw_list(f: &mut Frame, area: Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .zone_names
        .iter()
        .map(|n| {
            let z = &app.zones[n];
            let kind = zone_kind(z);
            let color = z.get("color").and_then(|x| x.as_str()).unwrap_or("-");
            let net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("-");
            let ip = z.get("ip").and_then(|x| x.as_str()).unwrap_or("-");
            let mem = z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0);
            let vcpu = z.get("vcpu").and_then(|x| x.as_u64()).unwrap_or(0);
            let line = if is_iso_zone(z) {
                format!(
                    "{n:<12} {kind:<11} {color:<7} ISO  {mem:>5}M {vcpu}c  {net:<5} {ip}  {}",
                    iso_label(z)
                )
            } else {
                let tmpl = z.get("template").and_then(|x| x.as_str()).unwrap_or("-");
                format!(
                    "{n:<12} {kind:<11} {color:<7} {tmpl:<7} {mem:>5}M {vcpu}c  {net:<5} {ip}"
                )
            };
            ListItem::new(line)
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(format!(
            "NAME         KIND        COLOR   TYPE    RAM  CPU NET   IP/ISO  ({})",
            app.zones_path.display()
        )))
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn draw_edit(f: &mut Frame, area: Rect, app: &App) {
    let Some(name) = app.selected_zone() else {
        f.render_widget(
            Paragraph::new("No zone selected").block(Block::default().borders(Borders::ALL)),
            area,
        );
        return;
    };
    let z = &app.zones[name];
    let kind = zone_kind(z);
    let iso = is_iso_zone(z);
    let apps = z
        .get("apps")
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "-".into());
    let usb = z
        .get("usb")
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "-".into());

    let mut lines = vec![
        Line::from(Span::styled(
            format!(
                "  {name}  ·  {}{}",
                kind,
                if iso { "  ·  ISO/HVM" } else { "  ·  NixOS" }
            ),
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(format!(
            "  [t] template   {}",
            z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
        )),
    ];
    if iso {
        lines.push(Line::from(format!(
            "  [o] iso path   {}",
            z.get("iso").and_then(|x| x.as_str()).unwrap_or("-")
        )));
        lines.push(Line::from(format!(
            "  [b] boot       {}  (iso|disk|both)",
            z.get("boot").and_then(|x| x.as_str()).unwrap_or("iso")
        )));
        lines.push(Line::from(format!(
            "      display    {}",
            z.get("display").and_then(|x| x.as_str()).unwrap_or("gtk")
        )));
    }
    lines.extend([
        Line::from(format!(
            "  [c] color      {}  {}   [n] rename",
            z.get("color").and_then(|x| x.as_str()).unwrap_or("-"),
            color_hex(z.get("color").and_then(|x| x.as_str()).unwrap_or("gray"))
        )),
        Line::from(format!(
            "  [i] internet   {}",
            z.get("internet").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [k] kind       {kind}  ← appvm | disposable | template"
        )),
        Line::from(format!(
            "  [m]/[M] RAM     {} MiB   (step)   [r] type exact",
            z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "  [v]/[V] vCPU    {}        (step)   [N] type exact",
            z.get("vcpu").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "      ip/mac     {}  /  {}",
            z.get("ip").and_then(|x| x.as_str()).unwrap_or("-"),
            z.get("mac").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "      socks      {}",
            z.get("socks").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!("  [u] usb add    {usb}")),
        Line::from("  [U] usb pop last"),
    ]);
    if iso {
        lines.push(Line::from("  [p] apps       (N/A — foreign ISO guest)"));
        lines.push(Line::from(""));
        lines.push(Line::from(
            "  ISO/HVM: same kind/color/net/usb. Start → QEMU GTK. docs/iso.md",
        ));
        lines.push(Line::from(
            "  After save: bunker-zone-start (rebuild only for GNOME launchers).",
        ));
    } else {
        lines.push(Line::from(format!("  [p] apps add   {apps}")));
        lines.push(Line::from("  [P] apps pop last"));
        lines.push(Line::from(""));
        lines.push(Line::from(
            "  Prefer this TUI / bunker-zone CLI. After save: nixos-rebuild switch.",
        ));
    }
    f.render_widget(
        Paragraph::new(lines).block(Block::default().borders(Borders::ALL).title("fields")),
        area,
    );
}

fn draw_help(f: &mut Frame, area: Rect) {
    let text = vec![
        Line::from("One CRUD for all zone types (zones.json):"),
        Line::from("  • a  = add NixOS AppVM (desktop/dev/browser/radio templates)"),
        Line::from("  • A/I = add ISO/HVM (Tails, other .iso) — same kind/color/net/usb"),
        Line::from("  • n  = rename zone   c = cycle color (icons + guest cursor)"),
        Line::from("  • k  = kind: appvm → disposable → template"),
        Line::from("  • m/M = RAM ±   v/V = vCPU ±   r/N = type exact MiB / cores"),
        Line::from("  • t  = template; o = ISO path; b = boot (ISO)"),
        Line::from(""),
        Line::from("List:  Enter edit  x delete  s start  w save"),
        Line::from("defaults · service = net/usb/voice/mat2 (ISO zones: net + usb matter most)."),
        Line::from("See docs/iso.md"),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    Rect {
        x,
        y,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}

fn move_sel(app: &mut App, delta: isize) {
    if app.zone_names.is_empty() {
        return;
    }
    let n = app.zone_names.len();
    let i = app.list.selected().unwrap_or(0) as isize + delta;
    let i = if i < 0 {
        n - 1
    } else if i as usize >= n {
        0
    } else {
        i as usize
    };
    app.list.select(Some(i));
}

fn run() -> io::Result<()> {
    let path = env::var_os("BUNKER_ZONES_JSON")
        .map(PathBuf::from)
        .or_else(|| {
            [
                dirs_home().join("nixos-bunker/config/zones.json"),
                PathBuf::from("/etc/bunker/zones.json"),
            ]
            .into_iter()
            .find(|p| p.is_file())
        })
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "set BUNKER_ZONES_JSON or place config/zones.json",
            )
        })?;

    let mut app = App::load(path)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let res = event_loop(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn dirs_home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn event_loop(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }

        if app.input_kind != InputKind::None {
            match key.code {
                KeyCode::Esc => {
                    app.input_kind = InputKind::None;
                    app.input.clear();
                    app.pending_name.clear();
                }
                KeyCode::Char('n') | KeyCode::Char('N')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                }
                KeyCode::Char('y') | KeyCode::Char('Y')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                    app.delete_selected();
                }
                KeyCode::Enter => {
                    let text = app.input.clone();
                    match app.input_kind {
                        InputKind::AddName => {
                            app.add_zone(&text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::AddIsoName => {
                            let name = text.trim().to_string();
                            if name.is_empty()
                                || !name
                                    .chars()
                                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                            {
                                app.status = "Name must be alphanumeric / _ / -".into();
                            } else if app.zones.contains_key(&name) {
                                app.status = format!("Zone exists: {name}");
                            } else {
                                app.pending_name = name;
                                app.input.clear();
                                app.input_kind = InputKind::AddIsoPath;
                                app.status = "Enter absolute path to .iso / .img".into();
                            }
                        }
                        InputKind::AddIsoPath => {
                            let name = app.pending_name.clone();
                            app.add_iso_zone(&name, &text);
                            app.pending_name.clear();
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::AddApp => {
                            app.push_list("apps", &text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::AddUsb => {
                            app.push_list("usb", &text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetIso => {
                            app.set_iso_path(&text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetMem => {
                            app.set_mem_mib(&text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetVcpu => {
                            app.set_vcpu_n(&text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::Rename => {
                            app.rename_zone(&text);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::ConfirmDelete | InputKind::None => {
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                    }
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(c) if app.input_kind != InputKind::ConfirmDelete => {
                    app.input.push(c);
                }
                _ => {}
            }
            continue;
        }

        match app.screen {
            Screen::List => match key.code {
                KeyCode::Char('q') => break,
                KeyCode::Char('?') => app.screen = Screen::Help,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_sel(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_sel(app, -1),
                KeyCode::Enter | KeyCode::Char('e') => {
                    if app.selected_zone().is_some() {
                        app.screen = Screen::Edit;
                    }
                }
                KeyCode::Char('a') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddName;
                }
                KeyCode::Char('A') | KeyCode::Char('I') => {
                    app.input.clear();
                    app.pending_name.clear();
                    app.input_kind = InputKind::AddIsoName;
                    app.status = "New ISO/HVM zone (Tails, …) — name then path".into();
                }
                KeyCode::Char('x') | KeyCode::Char('d') => {
                    if app.selected_zone().is_some() {
                        app.input_kind = InputKind::ConfirmDelete;
                    }
                }
                KeyCode::Char('s') => app.start_selected(),
                KeyCode::Char('c') if app.selected_zone().is_some() => {
                    app.cycle_str_field("color", COLORS);
                }
                KeyCode::Char('n') if app.selected_zone().is_some() => {
                    app.input = app.selected_zone().unwrap_or("").to_string();
                    app.input_kind = InputKind::Rename;
                }
                KeyCode::Char('m') => app.cycle_mem(true),
                KeyCode::Char('M') => app.cycle_mem(false),
                KeyCode::Char('v') => app.cycle_vcpu(true),
                KeyCode::Char('V') => app.cycle_vcpu(false),
                KeyCode::Char('r') if app.selected_zone().is_some() => {
                    app.input.clear();
                    if let Some(n) = app.selected_zone() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(m) = z.get("mem").and_then(|x| x.as_u64()) {
                                app.input = m.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetMem;
                }
                KeyCode::Char('N') if app.selected_zone().is_some() => {
                    app.input.clear();
                    if let Some(n) = app.selected_zone() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(c) = z.get("vcpu").and_then(|x| x.as_u64()) {
                                app.input = c.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetVcpu;
                }
                _ => {}
            },
            Screen::Edit => match key.code {
                KeyCode::Esc => app.screen = Screen::List,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Char('t') => {
                    app.cycle_str_field("template", TEMPLATES);
                    let is_iso = app
                        .selected_zone()
                        .and_then(|n| app.zones.get(n))
                        .map(is_iso_zone)
                        .unwrap_or(false);
                    if is_iso {
                        let empty = app
                            .selected_zone()
                            .and_then(|n| app.zones.get(n))
                            .and_then(|z| z.get("iso"))
                            .and_then(|x| x.as_str())
                            .unwrap_or("")
                            .is_empty();
                        if empty {
                            app.input.clear();
                            app.input_kind = InputKind::SetIso;
                            app.status = "template=iso — enter ISO path".into();
                        }
                    }
                }
                KeyCode::Char('o') => {
                    app.input.clear();
                    app.input_kind = InputKind::SetIso;
                }
                KeyCode::Char('b') => app.cycle_boot(),
                KeyCode::Char('c') => app.cycle_str_field("color", COLORS),
                KeyCode::Char('i') => app.cycle_str_field("internet", NET_MODES),
                KeyCode::Char('k') => app.toggle_kind(),
                KeyCode::Char('n') => {
                    app.input = app.selected_zone().unwrap_or("").to_string();
                    app.input_kind = InputKind::Rename;
                }
                KeyCode::Char('m') => app.cycle_mem(true),
                KeyCode::Char('M') => app.cycle_mem(false),
                KeyCode::Char('v') => app.cycle_vcpu(true),
                KeyCode::Char('V') => app.cycle_vcpu(false),
                KeyCode::Char('r') => {
                    app.input.clear();
                    if let Some(n) = app.selected_zone() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(m) = z.get("mem").and_then(|x| x.as_u64()) {
                                app.input = m.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetMem;
                }
                KeyCode::Char('N') => {
                    app.input.clear();
                    if let Some(n) = app.selected_zone() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(c) = z.get("vcpu").and_then(|x| x.as_u64()) {
                                app.input = c.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetVcpu;
                }
                KeyCode::Char('p') => {
                    let iso = app
                        .selected_zone()
                        .and_then(|n| app.zones.get(n))
                        .map(is_iso_zone)
                        .unwrap_or(false);
                    if iso {
                        app.status = "apps N/A for ISO/HVM zones".into();
                    } else {
                        app.input.clear();
                        app.input_kind = InputKind::AddApp;
                    }
                }
                KeyCode::Char('P') => {
                    let iso = app
                        .selected_zone()
                        .and_then(|n| app.zones.get(n))
                        .map(is_iso_zone)
                        .unwrap_or(false);
                    if iso {
                        app.status = "apps N/A for ISO/HVM zones".into();
                    } else {
                        app.pop_list("apps");
                    }
                }
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::AddUsb;
                }
                KeyCode::Char('U') => app.pop_list("usb"),
                KeyCode::Char('s') => app.start_selected(),
                KeyCode::Char('?') => app.screen = Screen::Help,
                _ => {}
            },
            Screen::Help => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q')) {
                    app.screen = Screen::List;
                }
            }
        }
    }
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("bunker-zones-tui: {e}");
        std::process::exit(1);
    }
}
