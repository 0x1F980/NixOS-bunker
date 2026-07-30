//! Deniable whole-zone VMs (Shufflecake layers): CRUD + unlock/lock = show/hide.
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
    env, fs, io,
    io::{Write as IoWrite, Stdout},
    path::PathBuf,
    process::{Command, Stdio},
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
    SetIso,
    SetMem,
    SetVcpu,
    Rename,
    UnlockPass,
    ConfirmDelete,
}

const TEMPLATES: &[&str] = &["desktop", "dev", "browser", "radio", "iso"];
const KINDS: &[&str] = &["appvm", "disposable", "template"];
const MEM_STEPS: &[u64] = &[
    512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384,
];
const VCPU_STEPS: &[u64] = &[1, 2, 4, 6, 8, 12, 16];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];

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

fn zone_kind(z: &Value) -> &str {
    match z.get("kind").and_then(|x| x.as_str()) {
        Some("template") => "template",
        Some("disposable") => "disposable",
        Some("appvm") => "appvm",
        _ if z.get("disposable").and_then(|x| x.as_bool()) == Some(true) => "disposable",
        _ => "appvm",
    }
}

struct App {
    path: PathBuf,
    zones: Map<String, Value>,
    names: Vec<String>,
    list: ListState,
    screen: Screen,
    status: String,
    dirty: bool,
    input: String,
    input_kind: InputKind,
    unlock_layer: u64,
    pending_name: String,
}

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let raw = if path.is_file() {
            fs::read_to_string(&path)?
        } else {
            "{}\n".into()
        };
        let v: Value = serde_json::from_str(&raw)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let zones = v.as_object().cloned().unwrap_or_default();
        let mut names: Vec<_> = zones.keys().cloned().collect();
        names.sort();
        let mut list = ListState::default();
        if !names.is_empty() {
            list.select(Some(0));
        }
        Ok(Self {
            path,
            zones,
            names,
            list,
            screen: Screen::List,
            status: "Hidden whole VMs on Shufflecake layers. Unlock = show in GNOME.".into(),
            dirty: false,
            input: String::new(),
            input_kind: InputKind::None,
            unlock_layer: 1,
            pending_name: String::new(),
        })
    }

    fn refresh(&mut self) {
        let sel = self.selected().map(|s| s.to_string());
        self.names = self.zones.keys().cloned().collect();
        self.names.sort();
        if let Some(n) = sel {
            if let Some(i) = self.names.iter().position(|x| x == &n) {
                self.list.select(Some(i));
                return;
            }
        }
        if self.names.is_empty() {
            self.list.select(None);
        } else {
            self.list.select(Some(0));
        }
    }

    fn selected(&self) -> Option<&str> {
        self.list.selected().map(|i| self.names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let pretty = serde_json::to_string_pretty(&Value::Object(self.zones.clone()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.path.with_extension("json.bak");
        let _ = fs::copy(&self.path, &bak);
        fs::write(&self.path, pretty + "\n")?;
        self.dirty = false;
        self.status = format!(
            "Saved {}. Rebuild guests: sudo nixos-rebuild switch --flake .#host",
            self.path.display()
        );
        let _ = Command::new("bunker-sflc").arg("sync-visible").status();
        Ok(())
    }

    fn next_free(&self) -> (String, String, u64) {
        let mut used_ip = std::collections::HashSet::new();
        let mut used_socks = std::collections::HashSet::new();
        let mut used_mac = std::collections::HashSet::new();
        // Also avoid colliding with public zones if readable
        for extra in [
            PathBuf::from("/etc/bunker/zones.json"),
            self.path
                .parent()
                .unwrap_or(std::path::Path::new("."))
                .join("zones.json"),
        ] {
            if let Ok(raw) = fs::read_to_string(&extra) {
                if let Ok(Value::Object(m)) = serde_json::from_str(&raw) {
                    for z in m.values() {
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
                    }
                }
            }
        }
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
        let ipn = (21u8..250).find(|i| !used_ip.contains(i)).unwrap_or(200);
        let socks = (1101u64..1200).find(|p| !used_socks.contains(p)).unwrap_or(1199);
        let macn = (0x21u8..0xfe).find(|i| !used_mac.contains(i)).unwrap_or(0xbb);
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
            self.status = "Name: alphanumeric / _ / -".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "layer": 1,
                "panic": true,
                "template": "browser",
                "kind": "appvm",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 1536,
                "vcpu": 2,
                "disposable": false,
                "color": "purple",
                "internet": "nym",
                "usb": [],
                "apps": []
            }),
        );
        self.refresh();
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!("Added deniable VM {name} on layer 1 (panic=true). Save + rebuild.");
    }

    fn delete_selected(&mut self) {
        let Some(name) = self.selected().map(|s| s.to_string()) else {
            return;
        };
        self.zones.remove(&name);
        self.refresh();
        self.dirty = true;
        self.screen = Screen::List;
        self.status = format!("Removed {name}");
    }

    fn rename_zone(&mut self, new_name: &str) {
        let new_name = new_name.trim();
        let Some(old) = self.selected().map(|s| s.to_string()) else {
            return;
        };
        if new_name.is_empty()
            || !new_name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name: alphanumeric / _ / -".into();
            return;
        }
        if new_name == old {
            self.status = "Name unchanged".into();
            return;
        }
        if self.zones.contains_key(new_name) {
            self.status = format!("exists: {new_name}");
            return;
        }
        let Some(val) = self.zones.remove(&old) else {
            return;
        };
        self.zones.insert(new_name.into(), val);
        self.refresh();
        if let Some(i) = self.names.iter().position(|n| n == new_name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.status = format!("Renamed {old} → {new_name} (save + rebuild)");
    }

    fn obj_mut(&mut self) -> Option<&mut Map<String, Value>> {
        let name = self.selected()?.to_string();
        self.zones.get_mut(&name)?.as_object_mut()
    }

    fn cycle_str(&mut self, key: &str, opts: &[&str]) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get(key).and_then(|x| x.as_str()).unwrap_or(opts[0]);
        let i = opts.iter().position(|m| *m == cur).unwrap_or(0);
        let next = opts[(i + 1) % opts.len()];
        obj.insert(key.into(), json!(next));
        self.dirty = true;
        if key == "color" {
            self.status = format!("color → {next} {}", color_hex(next));
        } else {
            self.status = format!("{key} → {next}");
        }
    }

    fn cycle_layer(&mut self) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get("layer").and_then(|x| x.as_u64()).unwrap_or(1);
        let next = if cur >= 3 { 0 } else { cur + 1 };
        obj.insert("layer".into(), json!(next));
        self.dirty = true;
        self.status = format!("layer → {next}");
    }

    fn toggle_panic(&mut self) {
        let Some(obj) = self.obj_mut() else {
            return;
        };
        let cur = obj.get("panic").and_then(|x| x.as_bool()).unwrap_or(false);
        obj.insert("panic".into(), json!(!cur));
        self.dirty = true;
        self.status = format!("panic → {}", !cur);
    }

    fn toggle_kind(&mut self) {
        let Some(obj) = self.obj_mut() else {
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
        let Some(obj) = self.obj_mut() else {
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
        self.dirty = true;
        self.status = format!("iso → {path}");
    }

    fn cycle_mem(&mut self, up: bool) {
        let Some(obj) = self.obj_mut() else {
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
        self.status = format!("RAM mem → {next} MiB");
    }

    fn cycle_vcpu(&mut self, up: bool) {
        let Some(obj) = self.obj_mut() else {
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
        self.status = format!("vCPU → {next}");
    }

    fn set_mem_mib(&mut self, raw: &str) {
        let s = raw.trim().to_lowercase().replace('m', "").replace("ib", "");
        let Ok(n) = s.parse::<u64>() else {
            self.status = "RAM: enter MiB, e.g. 4096".into();
            return;
        };
        if !(256..=65536).contains(&n) {
            self.status = "RAM must be 256..65536 MiB".into();
            return;
        }
        let Some(obj) = self.obj_mut() else {
            return;
        };
        obj.insert("mem".into(), json!(n));
        self.dirty = true;
        self.status = format!("RAM mem → {n} MiB");
    }

    fn set_vcpu_n(&mut self, raw: &str) {
        let Ok(n) = raw.trim().parse::<u64>() else {
            self.status = "vCPU: 1..64".into();
            return;
        };
        if !(1..=64).contains(&n) {
            self.status = "vCPU must be 1..64".into();
            return;
        }
        let Some(obj) = self.obj_mut() else {
            return;
        };
        obj.insert("vcpu".into(), json!(n));
        self.dirty = true;
        self.status = format!("vCPU → {n}");
    }

    fn add_iso_zone(&mut self, name: &str, iso_path: &str) {
        let name = name.trim();
        let iso_path = iso_path.trim();
        if name.is_empty()
            || !name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            self.status = "Name: alphanumeric / _ / -".into();
            return;
        }
        if iso_path.is_empty() {
            self.status = "Need ISO path".into();
            return;
        }
        if self.zones.contains_key(name) {
            self.status = format!("exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.next_free();
        self.zones.insert(
            name.into(),
            json!({
                "layer": 1,
                "panic": true,
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
                "apps": []
            }),
        );
        self.refresh();
        self.dirty = true;
        self.screen = Screen::Edit;
        self.status = format!("Added deniable ISO/HVM {name} — k=kind o=path w save");
    }

    fn unlock_selected_layer(&mut self, pass: &str) {
        let layer = if let Some(name) = self.selected() {
            self.zones
                .get(name)
                .and_then(|z| z.get("layer"))
                .and_then(|x| x.as_u64())
                .unwrap_or(self.unlock_layer)
        } else {
            self.unlock_layer
        };
        let mut child = match Command::new("bunker-sflc")
            .arg("unlock")
            .arg(layer.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                self.status = format!("bunker-sflc missing: {e}");
                return;
            }
        };
        if let Some(mut stdin) = child.stdin.take() {
            let _ = writeln!(stdin, "{pass}");
        }
        let out = child.wait_with_output().ok();
        let ok = out.as_ref().map(|o| o.status.success()).unwrap_or(false);
        self.status = if ok {
            format!("Unlocked layer {layer} — deniable VMs visible in GNOME")
        } else {
            let err = out
                .map(|o| String::from_utf8_lossy(&o.stderr).trim().to_string())
                .unwrap_or_default();
            format!("Unlock failed: {err}")
        };
    }

    fn lock_all(&mut self) {
        let _ = Command::new("bunker-sflc").args(["lock", "all"]).status();
        self.status = "Locked all deniable layers — VMs hidden".into();
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
    let dirty = if app.dirty { " [UNSAVED]" } else { "" };
    f.render_widget(
        Paragraph::new(format!("Deniable zone-VMs (Shufflecake){dirty}"))
            .style(Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD))
            .block(Block::default().borders(Borders::ALL)),
        chunks[0],
    );
    match app.screen {
        Screen::List => draw_list(f, chunks[1], app),
        Screen::Edit => draw_edit(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }
    let hint = match app.input_kind {
        InputKind::AddName => format!("new NixOS deniable> {}_", app.input),
        InputKind::AddIsoName => format!("new ISO deniable name> {}_", app.input),
        InputKind::AddIsoPath => format!(
            "ISO path for '{}'> {}_",
            app.pending_name, app.input
        ),
        InputKind::SetIso => format!("ISO path> {}_", app.input),
        InputKind::SetMem => format!("RAM MiB> {}_", app.input),
        InputKind::SetVcpu => format!("vCPU> {}_", app.input),
        InputKind::Rename => format!("rename to> {}_", app.input),
        InputKind::UnlockPass => format!("layer passphrase> {}_", "*".repeat(app.input.len())),
        InputKind::ConfirmDelete => "Delete deniable zone? y/n".into(),
        InputKind::None => match app.screen {
            Screen::List => {
                "↑↓  Enter=edit  a=NixOS  A=ISO  c=color  n=rename  m/M=RAM  u=unlock  w  ?"
                    .into()
            }
            Screen::Edit => {
                "n=rename  c=color  m/M=RAM  v/V=CPU  t/o/i/k  l=layer  p=panic  w  Esc".into()
            }
            Screen::Help => "Esc=back".into(),
        },
    };
    f.render_widget(
        Paragraph::new(Line::from(vec![
            Span::raw(hint),
            Span::raw(" | "),
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
            | InputKind::SetIso
            | InputKind::SetMem
            | InputKind::SetVcpu
            | InputKind::Rename
            | InputKind::UnlockPass
    ) {
        let area = centered(chunks[1], 72, 5);
        f.render_widget(Clear, area);
        let title = match app.input_kind {
            InputKind::UnlockPass => "passphrase (not stored)",
            InputKind::AddIsoName => "deniable ISO/HVM name",
            InputKind::AddIsoPath | InputKind::SetIso => "absolute path to .iso / .img",
            InputKind::SetMem => "RAM MiB",
            InputKind::SetVcpu => "vCPU count",
            InputKind::Rename => "new zone name",
            _ => "zone name",
        };
        let shown = if app.input_kind == InputKind::UnlockPass {
            "*".repeat(app.input.len())
        } else {
            app.input.clone()
        };
        f.render_widget(
            Paragraph::new(shown).block(Block::default().borders(Borders::ALL).title(title)),
            area,
        );
    }
}

fn draw_list(f: &mut Frame, area: Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .names
        .iter()
        .map(|n| {
            let z = &app.zones[n];
            let layer = z.get("layer").and_then(|x| x.as_u64()).unwrap_or(0);
            let panic = z.get("panic").and_then(|x| x.as_bool()).unwrap_or(false);
            let kind = zone_kind(z);
            let typ = if is_iso_zone(z) {
                "ISO"
            } else {
                z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
            };
            let mem = z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0);
            let vcpu = z.get("vcpu").and_then(|x| x.as_u64()).unwrap_or(0);
            ListItem::new(format!(
                "{n:<12} L{layer} {:<5} {kind:<10} {typ:<7} {mem:>5}M {vcpu}c",
                if panic { "PANIC" } else { "-" },
            ))
        })
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!("deniable VMs — {}", app.path.display())),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn draw_edit(f: &mut Frame, area: Rect, app: &App) {
    let Some(name) = app.selected() else {
        return;
    };
    let z = &app.zones[name];
    let iso = is_iso_zone(z);
    let kind = zone_kind(z);
    let mut lines = vec![
        Line::from(Span::styled(
            format!(
                "  {name}  ·  {}{}",
                kind,
                if iso { "  ·  ISO/HVM" } else { "  ·  NixOS" }
            ),
            Style::default()
                .fg(Color::Magenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(format!(
            "  [l] layer    {}",
            z.get("layer").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "  [p] panic    {}  (destroyed by panic · service)",
            z.get("panic").and_then(|x| x.as_bool()).unwrap_or(false)
        )),
        Line::from(format!(
            "  [t] template {}",
            z.get("template").and_then(|x| x.as_str()).unwrap_or("-")
        )),
    ];
    if iso {
        lines.push(Line::from(format!(
            "  [o] iso path {}",
            z.get("iso").and_then(|x| x.as_str()).unwrap_or("-")
        )));
    }
    lines.extend([
        Line::from(format!(
            "  [c] color    {}  {}   [n] rename",
            z.get("color").and_then(|x| x.as_str()).unwrap_or("-"),
            color_hex(z.get("color").and_then(|x| x.as_str()).unwrap_or("gray"))
        )),
        Line::from(format!(
            "  [i] internet {}",
            z.get("internet").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(format!(
            "  [k] kind     {kind}  ← appvm | disposable | template"
        )),
        Line::from(format!(
            "  [m]/[M] RAM   {} MiB   [r] exact",
            z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "  [v]/[V] vCPU  {}      [N] exact",
            z.get("vcpu").and_then(|x| x.as_u64()).unwrap_or(0)
        )),
        Line::from(format!(
            "      ip       {}",
            z.get("ip").and_then(|x| x.as_str()).unwrap_or("-")
        )),
        Line::from(""),
        Line::from("  Whole VM on Shufflecake when unlocked. ISO = QEMU HVM (docs/iso.md)."),
        Line::from("  Prefer this TUI — do not hand-edit Nix for deniable CRUD."),
    ]);
    f.render_widget(
        Paragraph::new(lines).block(Block::default().borders(Borders::ALL)),
        area,
    );
}

fn draw_help(f: &mut Frame, area: Rect) {
    let text = vec![
        Line::from("Deniable = entire zones (NixOS or ISO/HVM), not files."),
        Line::from("a = NixOS deniable · A/I = ISO/HVM deniable (Tails, …)."),
        Line::from("n = rename · c = color · k = kind · m/M RAM · v/V vCPU · o = ISO."),
        Line::from("Unlock layer → VMs appear under /run/bunker/xdg (GNOME)."),
        Line::from("See docs/deniable.md + docs/iso.md"),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    Rect {
        x: area.x + area.width.saturating_sub(width) / 2,
        y: area.y + area.height.saturating_sub(height) / 2,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}

fn move_sel(app: &mut App, d: isize) {
    if app.names.is_empty() {
        return;
    }
    let n = app.names.len() as isize;
    let i = app.list.selected().unwrap_or(0) as isize + d;
    let i = ((i % n) + n) % n;
    app.list.select(Some(i as usize));
}

fn resolve_path() -> PathBuf {
    if let Some(p) = env::var_os("BUNKER_DENIABLE_JSON") {
        return PathBuf::from(p);
    }
    for p in [
        PathBuf::from("/etc/bunker/deniable-zones.json"),
        env::var_os("HOME")
            .map(|h| PathBuf::from(h).join("nixos-bunker/config/deniable-zones.json"))
            .unwrap_or_default(),
    ] {
        if p.is_file() {
            return p;
        }
    }
    PathBuf::from("config/deniable-zones.json")
}

fn run() -> io::Result<()> {
    let mut app = App::load(resolve_path())?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    let res = loop_ui(&mut terminal, &mut app);
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn loop_ui(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
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
                KeyCode::Enter => {
                    let t = app.input.clone();
                    match app.input_kind {
                        InputKind::AddName => {
                            app.add_zone(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::AddIsoName => {
                            let name = t.trim().to_string();
                            if name.is_empty()
                                || !name
                                    .chars()
                                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                            {
                                app.status = "Name: alphanumeric / _ / -".into();
                            } else if app.zones.contains_key(&name) {
                                app.status = format!("exists: {name}");
                            } else {
                                app.pending_name = name;
                                app.input.clear();
                                app.input_kind = InputKind::AddIsoPath;
                            }
                        }
                        InputKind::AddIsoPath => {
                            let name = app.pending_name.clone();
                            app.add_iso_zone(&name, &t);
                            app.pending_name.clear();
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetIso => {
                            app.set_iso_path(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetMem => {
                            app.set_mem_mib(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::SetVcpu => {
                            app.set_vcpu_n(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::Rename => {
                            app.rename_zone(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::UnlockPass => {
                            app.unlock_selected_layer(&t);
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                        InputKind::ConfirmDelete | InputKind::None => {
                            app.input.clear();
                            app.input_kind = InputKind::None;
                        }
                    }
                }
                KeyCode::Char('y') | KeyCode::Char('Y')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                    app.delete_selected();
                }
                KeyCode::Char('n') | KeyCode::Char('N')
                    if app.input_kind == InputKind::ConfirmDelete =>
                {
                    app.input_kind = InputKind::None;
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(c) if app.input_kind != InputKind::ConfirmDelete => app.input.push(c),
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
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_sel(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_sel(app, -1),
                KeyCode::Enter | KeyCode::Char('e') => {
                    if app.selected().is_some() {
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
                    app.status = "Deniable ISO/HVM — name then path".into();
                }
                KeyCode::Char('x') => {
                    if app.selected().is_some() {
                        app.input_kind = InputKind::ConfirmDelete;
                    }
                }
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::UnlockPass;
                }
                KeyCode::Char('L') => app.lock_all(),
                KeyCode::Char('c') if app.selected().is_some() => {
                    app.cycle_str("color", COLORS);
                }
                KeyCode::Char('n') if app.selected().is_some() => {
                    app.input = app.selected().unwrap_or("").to_string();
                    app.input_kind = InputKind::Rename;
                }
                KeyCode::Char('m') => app.cycle_mem(true),
                KeyCode::Char('M') => app.cycle_mem(false),
                KeyCode::Char('v') => app.cycle_vcpu(true),
                KeyCode::Char('V') => app.cycle_vcpu(false),
                KeyCode::Char('r') if app.selected().is_some() => {
                    app.input.clear();
                    if let Some(n) = app.selected() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(m) = z.get("mem").and_then(|x| x.as_u64()) {
                                app.input = m.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetMem;
                }
                KeyCode::Char('N') if app.selected().is_some() => {
                    app.input.clear();
                    if let Some(n) = app.selected() {
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
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Char('t') => {
                    app.cycle_str("template", TEMPLATES);
                    let is_iso = app
                        .selected()
                        .and_then(|n| app.zones.get(n))
                        .map(is_iso_zone)
                        .unwrap_or(false);
                    if is_iso {
                        let empty = app
                            .selected()
                            .and_then(|n| app.zones.get(n))
                            .and_then(|z| z.get("iso"))
                            .and_then(|x| x.as_str())
                            .unwrap_or("")
                            .is_empty();
                        if empty {
                            app.input.clear();
                            app.input_kind = InputKind::SetIso;
                        }
                    }
                }
                KeyCode::Char('o') => {
                    app.input.clear();
                    app.input_kind = InputKind::SetIso;
                }
                KeyCode::Char('c') => app.cycle_str("color", COLORS),
                KeyCode::Char('i') => app.cycle_str("internet", NET_MODES),
                KeyCode::Char('k') => app.toggle_kind(),
                KeyCode::Char('n') => {
                    app.input = app.selected().unwrap_or("").to_string();
                    app.input_kind = InputKind::Rename;
                }
                KeyCode::Char('m') => app.cycle_mem(true),
                KeyCode::Char('M') => app.cycle_mem(false),
                KeyCode::Char('v') => app.cycle_vcpu(true),
                KeyCode::Char('V') => app.cycle_vcpu(false),
                KeyCode::Char('r') => {
                    app.input.clear();
                    if let Some(n) = app.selected() {
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
                    if let Some(n) = app.selected() {
                        if let Some(z) = app.zones.get(n) {
                            if let Some(c) = z.get("vcpu").and_then(|x| x.as_u64()) {
                                app.input = c.to_string();
                            }
                        }
                    }
                    app.input_kind = InputKind::SetVcpu;
                }
                KeyCode::Char('l') => app.cycle_layer(),
                KeyCode::Char('p') => app.toggle_panic(),
                KeyCode::Char('u') => {
                    app.input.clear();
                    app.input_kind = InputKind::UnlockPass;
                }
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
        eprintln!("bunker-deniable-tui: {e}");
        std::process::exit(1);
    }
}
