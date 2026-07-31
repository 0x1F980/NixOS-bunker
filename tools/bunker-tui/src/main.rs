//! bunker — full operator TUI (CRUD + start/usb/host-net/sflc) for non-experts.
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame, Terminal,
};
use serde_json::{json, Map, Value};
use std::{
    env, fs,
    io::{self, Write, Stdout},
    path::PathBuf,
    process::{Command, Stdio},
};

const NET: &[&str] = &["nym", "i2p", "tor", "none"];
const KIND: &[&str] = &["appvm", "disposable", "template"];
const PANIC: &[&str] = &["keep", "lock", "wipe"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const HELP: &str = "s start  v usb  h host-net  b sflc-boot  |  a add  d del  r rename  c color  t type  n net  i hide  u unlock  o iso  f file  Space panic  p ARM  w save  q";

#[derive(Clone)]
enum Mode {
    List,
    Panic,
    Add,
    Rename,
    Iso,
    Delete,
    FileCopy,
    UnlockLayer,
    UnlockPass,
    Start,
    Usb,
    HostNet,
    BootstrapPass,
}

struct App {
    path: PathBuf,
    zones: Map<String, Value>,
    names: Vec<String>,
    list: ListState,
    status: String,
    dirty: bool,
    mode: Mode,
    input: String,
    unlock_layer: String,
    boot_passes: Vec<String>,
    boot_need: usize,
}

fn is_hidden(z: &Value) -> bool {
    flag(z, "invisible")
        || z.get("slot")
            .and_then(|x| x.as_str())
            .is_some_and(|s| !s.is_empty())
}

fn slots_path() -> Option<PathBuf> {
    [
        PathBuf::from("config/slots.json"),
        PathBuf::from("/etc/bunker/slots.json"),
    ]
    .into_iter()
    .find(|p| p.is_file())
}

fn load_slots() -> Map<String, Value> {
    let Some(p) = slots_path() else {
        return Map::new();
    };
    serde_json::from_str(&fs::read_to_string(p).unwrap_or_default())
        .ok()
        .and_then(|v: Value| v.as_object().cloned())
        .unwrap_or_default()
}

fn merged_path() -> PathBuf {
    PathBuf::from("/run/bunker/zones-merged.json")
}

fn unlocked_layers() -> Vec<u64> {
    fs::read_to_string("/run/bunker/unlocked-layers")
        .unwrap_or_default()
        .lines()
        .filter_map(|s| s.trim().parse().ok())
        .collect()
}

fn flag(z: &Value, k: &str) -> bool {
    match z.get(k) {
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => matches!(s.to_lowercase().as_str(), "on" | "true" | "1" | "yes"),
        _ => false,
    }
}

fn kind_of(z: &Value) -> &str {
    z.get("kind")
        .and_then(|x| x.as_str())
        .filter(|s| KIND.contains(s))
        .unwrap_or(if flag(z, "disposable") {
            "disposable"
        } else {
            "appvm"
        })
}

fn panic_of(z: &Value) -> &str {
    z.get("panic")
        .and_then(|v| v.as_str())
        .filter(|s| PANIC.contains(s))
        .unwrap_or("keep")
}

fn valid_name(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

fn trim_msg(s: &str) -> String {
    s.trim().chars().take(140).collect()
}

fn sflc_max_layers() -> usize {
    for p in [
        "/etc/bunker/shufflecake.json",
        "config/shufflecake.json",
    ] {
        if let Ok(t) = fs::read_to_string(p) {
            if let Ok(v) = serde_json::from_str::<Value>(&t) {
                if let Some(n) = v.get("max_layers").and_then(|x| x.as_u64()) {
                    return (n as usize).clamp(1, 15);
                }
            }
        }
    }
    3
}

/// Prefer sudo (nft/microvm/sflc need root); fall back to bare command.
fn run_root(bin: &str, args: &[&str]) -> (bool, String) {
    let try_one = |use_sudo: bool| -> io::Result<(bool, String)> {
        let mut c = if use_sudo {
            let mut c = Command::new("sudo");
            c.arg(bin).args(args);
            c
        } else {
            let mut c = Command::new(bin);
            c.args(args);
            c
        };
        let o = c.output()?;
        let body = if o.status.success() {
            String::from_utf8_lossy(&o.stdout).into_owned()
        } else {
            let e = String::from_utf8_lossy(&o.stderr);
            let out = String::from_utf8_lossy(&o.stdout);
            if e.trim().is_empty() {
                out.into_owned()
            } else {
                e.into_owned()
            }
        };
        Ok((o.status.success(), body))
    };
    match try_one(true) {
        Ok((true, b)) => (true, b),
        Ok((false, b)) => match try_one(false) {
            Ok((ok2, b2)) if ok2 => (true, b2),
            Ok((_, b2)) => (false, if b.trim().is_empty() { b2 } else { b }),
            Err(_) => (false, b),
        },
        Err(_) => match try_one(false) {
            Ok(r) => r,
            Err(e) => (false, e.to_string()),
        },
    }
}

fn run_root_stdin(bin: &str, args: &[&str], stdin_data: &str) -> (bool, String) {
    let spawn = |use_sudo: bool| -> io::Result<(bool, String)> {
        let mut c = if use_sudo {
            let mut c = Command::new("sudo");
            c.arg(bin).args(args);
            c
        } else {
            let mut c = Command::new(bin);
            c.args(args);
            c
        };
        c.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = c.spawn()?;
        if let Some(mut sin) = child.stdin.take() {
            sin.write_all(stdin_data.as_bytes())?;
        }
        let o = child.wait_with_output()?;
        let body = if o.status.success() {
            String::from_utf8_lossy(&o.stdout).into_owned()
        } else {
            String::from_utf8_lossy(&o.stderr).into_owned()
        };
        Ok((o.status.success(), body))
    };
    match spawn(true) {
        Ok((true, b)) => (true, b),
        Ok((false, b)) => match spawn(false) {
            Ok((ok2, b2)) if ok2 => (true, b2),
            Ok((_, b2)) => (false, if b.trim().is_empty() { b2 } else { b }),
            Err(_) => (false, b),
        },
        Err(_) => match spawn(false) {
            Ok(r) => r,
            Err(e) => (false, e.to_string()),
        },
    }
}

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let mut app = Self {
            path,
            zones: Map::new(),
            names: vec![],
            list: ListState::default(),
            status: HELP.into(),
            dirty: false,
            mode: Mode::List,
            input: String::new(),
            unlock_layer: String::new(),
            boot_passes: vec![],
            boot_need: sflc_max_layers(),
        };
        app.reload_view()?;
        Ok(app)
    }

    /// Display = merged (public ∪ unlocked hidden) when available; else public only.
    fn reload_view(&mut self) -> io::Result<()> {
        let src = if merged_path().is_file() {
            merged_path()
        } else {
            self.path.clone()
        };
        let v: Value = serde_json::from_str(&fs::read_to_string(&src)?)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        self.zones = v
            .as_object()
            .cloned()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "bad zones.json"))?;
        // Never show locked hidden (no slot in public file anyway; belt+suspenders)
        self.zones.retain(|_, z| !is_hidden(z) || unlocked_layers().contains(
            &z.get("layer").and_then(|x| x.as_u64()).unwrap_or(0),
        ));
        self.refresh_names();
        Ok(())
    }

    fn refresh_names(&mut self) {
        self.names = self.zones.keys().cloned().collect();
        self.names.sort();
        if self.names.is_empty() {
            self.list.select(None);
        } else {
            let i = self.list.selected().unwrap_or(0).min(self.names.len() - 1);
            self.list.select(Some(i));
        }
    }

    fn sel(&self) -> Option<&str> {
        self.list
            .selected()
            .and_then(|i| self.names.get(i))
            .map(|s| s.as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        // Split: public (no slot) → zones.json; hidden by layer → SFLC write-hidden
        let mut public = Map::new();
        let mut by_layer: std::collections::BTreeMap<u64, Map<String, Value>> =
            std::collections::BTreeMap::new();
        for (name, z) in &self.zones {
            if is_hidden(z) {
                let L = z.get("layer").and_then(|x| x.as_u64()).unwrap_or(1);
                let slot = z
                    .get("slot")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string();
                let mut hz = Map::new();
                hz.insert("slot".into(), json!(slot));
                hz.insert("layer".into(), json!(L));
                for k in ["color", "internet", "panic", "template", "kind"] {
                    if let Some(v) = z.get(k) {
                        hz.insert(k.into(), v.clone());
                    }
                }
                if let Some(usb) = z.get("usb") {
                    hz.insert("usb".into(), usb.clone());
                }
                if let Some(apps) = z.get("apps") {
                    hz.insert("apps".into(), apps.clone());
                }
                by_layer.entry(L).or_default().insert(name.clone(), Value::Object(hz));
            } else {
                let mut o = z.as_object().cloned().unwrap_or_default();
                o.remove("invisible");
                o.remove("layer");
                o.remove("slot");
                public.insert(name.clone(), Value::Object(o));
            }
        }
        // Ensure unlocked layers get an explicit write (possibly empty = clear)
        for L in unlocked_layers() {
            by_layer.entry(L).or_default();
        }
        fs::write(
            &self.path,
            serde_json::to_string_pretty(&Value::Object(public))?,
        )?;
        for (L, hzmap) in by_layer {
            let body = serde_json::to_string_pretty(&Value::Object(hzmap))?;
            let (ok, msg) = run_root_stdin(
                "bunker-sflc",
                &["write-hidden", &L.to_string()],
                &format!("{body}\n"),
            );
            if !ok {
                self.status = format!("save public OK; hidden L{L}: {}", trim_msg(&msg));
                self.dirty = true;
                return Ok(());
            }
        }
        let _ = run_root("bunker-sflc", &["sync"]);
        let _ = self.reload_view();
        self.dirty = false;
        self.status = format!("saved {}", self.path.display());
        Ok(())
    }

    fn cycle(&mut self, key: &str, modes: &[&str]) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let cur = self.zones[&n]
            .get(key)
            .and_then(|x| x.as_str())
            .unwrap_or(modes[0]);
        let i = modes.iter().position(|m| *m == cur).unwrap_or(0);
        let next = modes[(i + 1) % modes.len()];
        let o = self.zones.get_mut(&n).unwrap().as_object_mut().unwrap();
        o.insert(key.into(), json!(next));
        if key == "kind" {
            o.insert("disposable".into(), json!(next == "disposable"));
        }
        self.dirty = true;
        self.status = format!("{n}: {key} → {next}");
    }

    fn cycle_kind(&mut self) {
        self.cycle("kind", KIND);
    }

    fn cycle_color(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let cur = self.zones[&n]
            .get("color")
            .and_then(|x| x.as_str())
            .unwrap_or("gray");
        let i = COLORS.iter().position(|m| *m == cur).unwrap_or(0);
        let next = COLORS[(i + 1) % COLORS.len()];
        self.zones
            .get_mut(&n)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .insert("color".into(), json!(next));
        self.dirty = true;
        self.status = format!("{n}: color → {next} (icon + terminal)");
    }

    fn toggle_invisible(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let hidden = is_hidden(&self.zones[&n]);
        if hidden {
            // Unhide → public (drops slot; guest becomes public name — needs rebuild if was slot-only)
            let o = self.zones.get_mut(&n).unwrap().as_object_mut().unwrap();
            o.remove("invisible");
            o.remove("layer");
            o.remove("slot");
            self.dirty = true;
            self.status = format!("{n}: hide → no (public; w save)");
            return;
        }
        let unlocked = unlocked_layers();
        if unlocked.is_empty() {
            self.status = "hide: unlock a Shufflecake layer first (u)".into();
            return;
        }
        let L = unlocked[0];
        let slots = load_slots();
        if slots.is_empty() {
            self.status = "hide: no slots.json (rebuild host)".into();
            return;
        }
        let used: std::collections::HashSet<String> = self
            .zones
            .values()
            .filter_map(|z| z.get("slot").and_then(|x| x.as_str()).map(str::to_string))
            .collect();
        let Some(slot_id) = slots.keys().find(|k| !used.contains(*k)).cloned() else {
            self.status = "hide: all deniable slots in use".into();
            return;
        };
        // Overlay slot build fields into the zone for runtime IP/template display
        if let Some(slot_cfg) = slots.get(&slot_id).and_then(|v| v.as_object()) {
            let o = self.zones.get_mut(&n).unwrap().as_object_mut().unwrap();
            for (k, v) in slot_cfg {
                if matches!(
                    k.as_str(),
                    "ip" | "mac" | "socks" | "template" | "mem" | "vcpu" | "internet" | "kind"
                ) {
                    o.insert(k.clone(), v.clone());
                }
            }
            o.insert("slot".into(), json!(slot_id));
            o.insert("invisible".into(), json!(true));
            o.insert("layer".into(), json!(L));
        }
        self.dirty = true;
        self.status = format!("{n}: hide → yes slot={slot_id} L{L} (w save)");
    }

    fn add_zone(&mut self, name: String) {
        if !valid_name(&name) || self.zones.contains_key(&name) {
            self.status = "bad or duplicate name".into();
            return;
        }
        // next free-ish IP
        let used: Vec<u8> = self
            .zones
            .values()
            .filter_map(|z| z.get("ip").and_then(|x| x.as_str()))
            .filter_map(|ip| ip.strip_prefix("10.0.0.").and_then(|s| s.parse().ok()))
            .collect();
        let mut n = 20u8;
        while used.contains(&n) {
            n = n.saturating_add(1);
        }
        self.zones.insert(
            name.clone(),
            json!({
                "template": "desktop",
                "kind": "appvm",
                "ip": format!("10.0.0.{n}"),
                "mac": format!("02:b0:00:00:00:{n:02x}"),
                "socks": 1080 + n as u16,
                "mem": 1536,
                "diskGb": 16,
                "vcpu": 2,
                "disposable": false,
                "color": "red",
                "internet": "tor",
                "usb": [],
                "apps": [],
                "panic": "keep"
            }),
        );
        self.refresh_names();
        if let Some(i) = self.names.iter().position(|x| x == &name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.status = format!("added {name} — set type/color/net, then w save");
    }

    fn rename_zone(&mut self, new: String) {
        let Some(old) = self.sel().map(str::to_string) else {
            return;
        };
        if !valid_name(&new) || self.zones.contains_key(&new) {
            self.status = "bad or duplicate name".into();
            return;
        }
        if let Some(z) = self.zones.remove(&old) {
            self.zones.insert(new.clone(), z);
            self.refresh_names();
            if let Some(i) = self.names.iter().position(|x| x == &new) {
                self.list.select(Some(i));
            }
            self.dirty = true;
            self.status = format!("renamed {old} → {new}");
        }
    }

    fn set_iso(&mut self, path: String) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let o = self.zones.get_mut(&n).unwrap().as_object_mut().unwrap();
        if path.is_empty() {
            o.remove("iso");
            if o.get("template").and_then(|x| x.as_str()) == Some("iso") {
                o.insert("template".into(), json!("desktop"));
            }
            o.remove("boot");
            self.status = format!("{n}: ISO cleared");
        } else {
            o.insert("template".into(), json!("iso"));
            o.insert("iso".into(), json!(path.clone()));
            o.insert("boot".into(), json!("iso"));
            if o.get("mem").and_then(|x| x.as_u64()).unwrap_or(0) < 2048 {
                o.insert("mem".into(), json!(2048));
            }
            self.status = format!("{n}: ISO → {path}");
        }
        self.dirty = true;
    }

    fn delete_zone(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        self.zones.remove(&n);
        self.refresh_names();
        self.dirty = true;
        self.status = format!("deleted {n}");
    }

    fn run_panic(&mut self) {
        let pass = std::mem::take(&mut self.input);
        self.mode = Mode::List;
        match Command::new("sudo")
            .arg("bunker-panic")
            .env("BUNKER_PANIC_PASS", &pass)
            .output()
            .or_else(|_| {
                Command::new("bunker-panic")
                    .env("BUNKER_PANIC_PASS", &pass)
                    .output()
            }) {
            Ok(o) if o.status.success() => self.status = "panic OK — reboot".into(),
            Ok(o) => {
                self.status = format!("panic: {}", trim_msg(&String::from_utf8_lossy(&o.stderr)))
            }
            Err(e) => self.status = format!("panic: {e}"),
        }
    }

    fn run_file_copy(&mut self) {
        let line = std::mem::take(&mut self.input);
        self.mode = Mode::List;
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() != 2 || !parts[0].contains(':') || !parts[1].contains(':') {
            self.status = "file: use srcZone:/path dstZone:/path".into();
            return;
        }
        let (ok, msg) = run_root("bunker-file", &["copy", parts[0], parts[1]]);
        self.status = if ok {
            format!("OK {}", trim_msg(&msg))
        } else {
            format!("file: {}", trim_msg(&msg))
        };
    }

    fn run_unlock(&mut self, layer: String) {
        let pass = std::mem::take(&mut self.input);
        self.mode = Mode::List;
        let (ok, msg) = run_root_stdin("bunker-sflc", &["unlock", &layer], &format!("{pass}\n"));
        if ok {
            let _ = self.reload_view();
            self.status = format!("unlocked L{layer} — hidden zones visible");
        } else {
            self.status = format!("unlock: {}", trim_msg(&msg));
        }
    }

    fn run_start(&mut self) {
        let target = self.input.trim().to_string();
        self.mode = Mode::List;
        self.input.clear();
        if target.is_empty() {
            self.status = "start: type net | usb | all | <zone>".into();
            return;
        }
        let (ok, msg) = run_root("bunker-zone-start", &[&target]);
        self.status = if ok {
            format!("started {target} — {}", trim_msg(&msg))
        } else {
            format!("start: {}", trim_msg(&msg))
        };
    }

    fn run_usb(&mut self) {
        let raw = self.input.trim().to_string();
        self.mode = Mode::List;
        self.input.clear();
        let Some(zone) = self.sel().map(str::to_string) else {
            self.status = "usb: select a zone first".into();
            return;
        };
        let detach = raw.starts_with('-') || raw.starts_with("detach ");
        let id = raw
            .trim_start_matches('-')
            .trim_start_matches("detach ")
            .trim();
        if !id.contains(':') {
            self.status = "usb: type vid:pid (prefix - to detach)".into();
            return;
        }
        let (ok, msg) = if detach {
            run_root("bunker-usb-detach", &[&zone, id])
        } else {
            run_root("bunker-usb-attach", &[&zone, id])
        };
        self.status = if ok {
            format!("OK usb {zone} — {}", trim_msg(&msg))
        } else {
            format!("usb: {}", trim_msg(&msg))
        };
    }

    fn run_host_net(&mut self, action: &str) {
        self.mode = Mode::List;
        let (ok, msg) = run_root("bunker-host-net", &[action]);
        self.status = if ok {
            format!("host-net {action}: {}", trim_msg(&msg))
        } else {
            format!("host-net: {}", trim_msg(&msg))
        };
    }

    fn bootstrap_push_pass(&mut self) {
        let p = std::mem::take(&mut self.input);
        if p.is_empty() {
            self.status = "empty passphrase".into();
            return;
        }
        self.boot_passes.push(p);
        if self.boot_passes.len() >= self.boot_need {
            let stdin_data = self
                .boot_passes
                .iter()
                .map(|s| format!("{s}\n"))
                .collect::<String>();
            self.boot_passes.clear();
            self.mode = Mode::List;
            let (ok, msg) = run_root_stdin("bunker-sflc", &["bootstrap"], &stdin_data);
            self.status = if ok {
                format!("sflc bootstrap OK — {}", trim_msg(&msg))
            } else {
                format!("bootstrap: {}", trim_msg(&msg))
            };
        } else {
            self.status = format!(
                "layer {}/{} passphrase next",
                self.boot_passes.len() + 1,
                self.boot_need
            );
        }
    }
}

fn draw(f: &mut Frame, app: &App) {
    let c = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(5), Constraint::Length(3)])
        .split(f.area());

    match &app.mode {
        Mode::Panic => {
            f.render_widget(
                Paragraph::new(format!("PANIC code: {}_  (Enter arm · Esc cancel)", app.input))
                    .block(Block::default().borders(Borders::ALL).title("PANIC")),
                c[0],
            );
        }
        Mode::Add => {
            f.render_widget(
                Paragraph::new(format!("New zone name: {}_", app.input)).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title("ADD zone"),
                ),
                c[0],
            );
        }
        Mode::Rename => {
            let cur = app.sel().unwrap_or("?");
            f.render_widget(
                Paragraph::new(format!("Rename '{cur}' → {}_", app.input)).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title("RENAME"),
                ),
                c[0],
            );
        }
        Mode::Iso => {
            let cur = app.sel().unwrap_or("?");
            f.render_widget(
                Paragraph::new(format!(
                    "ISO path for '{cur}': {}_  (empty=clear · Enter)",
                    app.input
                ))
                .block(Block::default().borders(Borders::ALL).title("ISO")),
                c[0],
            );
        }
        Mode::Delete => {
            let cur = app.sel().unwrap_or("?");
            f.render_widget(
                Paragraph::new(format!("Delete '{cur}'?  y=yes  Esc=cancel")).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title("DELETE"),
                ),
                c[0],
            );
        }
        Mode::FileCopy => {
            f.render_widget(
                Paragraph::new(format!(
                    "FILE COPY between VMs (1→1 via host)\nsrcZone:/path  dstZone:/path\n{}_",
                    app.input
                ))
                .block(Block::default().borders(Borders::ALL).title("FILE")),
                c[0],
            );
        }
        Mode::UnlockLayer => {
            f.render_widget(
                Paragraph::new(format!("Unlock Shufflecake layer #: {}_", app.input)).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title("SFLC UNLOCK"),
                ),
                c[0],
            );
        }
        Mode::UnlockPass => {
            let stars = "*".repeat(app.input.len());
            f.render_widget(
                Paragraph::new(format!("Layer passphrase: {stars}_")).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title("SFLC PASSPHRASE"),
                ),
                c[0],
            );
        }
        Mode::Start => {
            f.render_widget(
                Paragraph::new(format!(
                    "START broker or zone (netVM/usbVM = 1→many)\n\
                     type:  net  |  usb  |  all  |  <zone>\n\
                     {}_",
                    app.input
                ))
                .block(Block::default().borders(Borders::ALL).title("START")),
                c[0],
            );
        }
        Mode::Usb => {
            let cur = app.sel().unwrap_or("(select zone)");
            f.render_widget(
                Paragraph::new(format!(
                    "USB I/O via usbVM → zone '{cur}' (1 device → 1 zone)\n\
                     type vid:pid     eg 0bda:2838\n\
                     prefix - to detach   eg -0bda:2838\n\
                     {}_",
                    app.input
                ))
                .block(Block::default().borders(Borders::ALL).title("USB")),
                c[0],
            );
        }
        Mode::HostNet => {
            f.render_widget(
                Paragraph::new(
                    "HOST CLEARNET (updates only — keep locked for daily use)\n\n\
                     a = allow WAN   (nixos-rebuild)\n\
                     l = lock WAN    (safe default)\n\
                     t = status\n\
                     Esc = cancel",
                )
                .block(Block::default().borders(Borders::ALL).title("HOST-NET")),
                c[0],
            );
        }
        Mode::BootstrapPass => {
            let n = app.boot_passes.len() + 1;
            let stars = "*".repeat(app.input.len());
            f.render_widget(
                Paragraph::new(format!(
                    "Shufflecake FIRST-TIME bootstrap\n\
                     Passphrase for layer {n} of {}\n\
                     {stars}_",
                    app.boot_need
                ))
                .block(Block::default().borders(Borders::ALL).title("SFLC BOOTSTRAP")),
                c[0],
            );
        }
        Mode::List => {
            let items: Vec<ListItem> = app
                .names
                .iter()
                .map(|n| {
                    let z = &app.zones[n];
                    let iso = z.get("template").and_then(|x| x.as_str()) == Some("iso")
                        || z
                            .get("iso")
                            .and_then(|x| x.as_str())
                            .is_some_and(|s| !s.is_empty());
                    ListItem::new(format!(
                        "{n:<12} {kind:<11} {color:<7} net={net:<4} hide={hide} panic={panic}{iso}",
                        kind = kind_of(z),
                        color = z.get("color").and_then(|x| x.as_str()).unwrap_or("gray"),
                        net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("nym"),
                        hide = if is_hidden(z) { "yes" } else { "-" },
                        panic = panic_of(z),
                        iso = if iso { " [ISO]" } else { "" },
                    ))
                })
                .collect();
            let mut st = app.list.clone();
            f.render_stateful_widget(
                List::new(items)
                    .block(
                        Block::default()
                            .borders(Borders::ALL)
                            .title("bunker · zones  (? help)"),
                    )
                    .highlight_style(
                        Style::default()
                            .fg(Color::Cyan)
                            .add_modifier(Modifier::BOLD),
                    ),
                c[0],
                &mut st,
            );
        }
    }

    let foot = if app.dirty {
        format!("{}  [unsaved · press w]", app.status)
    } else {
        app.status.clone()
    };
    f.render_widget(
        Paragraph::new(foot).block(Block::default().borders(Borders::ALL)),
        c[1],
    );
}

fn main() -> io::Result<()> {
    let path = env::var_os("BUNKER_ZONES_JSON")
        .map(PathBuf::from)
        .or_else(|| {
            [
                PathBuf::from("config/zones.json"),
                PathBuf::from("/etc/bunker/zones.json"),
            ]
            .into_iter()
            .find(|p| p.is_file())
        })
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "zones.json"))?;
    let mut app = App::load(path)?;
    enable_raw_mode()?;
    let mut out = io::stdout();
    execute!(out, EnterAlternateScreen)?;
    let mut term = Terminal::new(CrosstermBackend::new(out))?;
    let r = run(&mut term, &mut app);
    disable_raw_mode()?;
    execute!(term.backend_mut(), LeaveAlternateScreen)?;
    r
}

fn text_input(app: &mut App, k: KeyCode, on_enter: impl FnOnce(&mut App)) {
    match k {
        KeyCode::Esc => {
            app.mode = Mode::List;
            app.input.clear();
            app.boot_passes.clear();
            app.status = HELP.into();
        }
        KeyCode::Enter => on_enter(app),
        KeyCode::Backspace => {
            app.input.pop();
        }
        KeyCode::Char(ch) => app.input.push(ch),
        _ => {}
    }
}

fn run(term: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        term.draw(|f| draw(f, app))?;
        let Event::Key(k) = event::read()? else {
            continue;
        };
        if k.kind != KeyEventKind::Press {
            continue;
        }

        match app.mode.clone() {
            Mode::List => match k.code {
                KeyCode::Char('q') => return Ok(()),
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save: {e}");
                    }
                }
                KeyCode::Char('?') => app.status = HELP.into(),
                KeyCode::Down | KeyCode::Char('j') => {
                    let i = app.list.selected().unwrap_or(0);
                    app.list
                        .select(Some((i + 1).min(app.names.len().saturating_sub(1))));
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    let i = app.list.selected().unwrap_or(0);
                    app.list.select(Some(i.saturating_sub(1)));
                }
                KeyCode::Char('t') => app.cycle_kind(),
                KeyCode::Char('n') => app.cycle("internet", NET),
                KeyCode::Char(' ') => app.cycle("panic", PANIC),
                KeyCode::Char('c') => app.cycle_color(),
                KeyCode::Char('i') => app.toggle_invisible(),
                KeyCode::Char('a') => {
                    app.mode = Mode::Add;
                    app.input.clear();
                    app.status = "type new zone name, Enter".into();
                }
                KeyCode::Char('r') => {
                    if app.sel().is_some() {
                        app.mode = Mode::Rename;
                        app.input.clear();
                        app.status = "type new name, Enter".into();
                    }
                }
                KeyCode::Char('o') => {
                    if app.sel().is_some() {
                        app.mode = Mode::Iso;
                        app.input = app
                            .sel()
                            .and_then(|n| app.zones[n].get("iso"))
                            .and_then(|x| x.as_str())
                            .unwrap_or("")
                            .to_string();
                        app.status = "ISO path (empty clears), Enter".into();
                    }
                }
                KeyCode::Char('d') => {
                    if app.sel().is_some() {
                        app.mode = Mode::Delete;
                        app.status = "confirm delete".into();
                    }
                }
                KeyCode::Char('p') => {
                    app.mode = Mode::Panic;
                    app.input.clear();
                    app.status = "type panic passphrase, Enter".into();
                }
                KeyCode::Char('f') => {
                    app.mode = Mode::FileCopy;
                    app.input.clear();
                    app.status = "file copy between VMs".into();
                }
                KeyCode::Char('u') => {
                    app.mode = Mode::UnlockLayer;
                    app.input.clear();
                    app.status = "sflc unlock: layer number".into();
                }
                KeyCode::Char('s') => {
                    app.mode = Mode::Start;
                    app.input = app.sel().unwrap_or("net").to_string();
                    app.status = "start net | usb | all | zone".into();
                }
                KeyCode::Char('v') => {
                    if app.sel().is_none() {
                        app.status = "select a zone, then v for USB".into();
                    } else {
                        app.mode = Mode::Usb;
                        app.input.clear();
                        app.status = "USB vid:pid (or -vid:pid detach)".into();
                    }
                }
                KeyCode::Char('h') => {
                    app.mode = Mode::HostNet;
                    app.status = "host-net: a allow · l lock · t status".into();
                }
                KeyCode::Char('b') => {
                    app.boot_need = sflc_max_layers();
                    app.boot_passes.clear();
                    app.mode = Mode::BootstrapPass;
                    app.input.clear();
                    app.status = format!("sflc bootstrap: layer 1/{}", app.boot_need);
                }
                _ => {}
            },
            Mode::Panic => text_input(app, k.code, |a| a.run_panic()),
            Mode::Add => text_input(app, k.code, |a| {
                let name = a.input.trim().to_string();
                a.mode = Mode::List;
                a.input.clear();
                a.add_zone(name);
            }),
            Mode::Rename => text_input(app, k.code, |a| {
                let name = a.input.trim().to_string();
                a.mode = Mode::List;
                a.input.clear();
                a.rename_zone(name);
            }),
            Mode::Iso => text_input(app, k.code, |a| {
                let path = a.input.trim().to_string();
                a.mode = Mode::List;
                a.input.clear();
                a.set_iso(path);
            }),
            Mode::Delete => match k.code {
                KeyCode::Esc | KeyCode::Char('n') => {
                    app.mode = Mode::List;
                    app.status = HELP.into();
                }
                KeyCode::Char('y') | KeyCode::Enter => {
                    app.mode = Mode::List;
                    app.delete_zone();
                }
                _ => {}
            },
            Mode::FileCopy => text_input(app, k.code, |a| a.run_file_copy()),
            Mode::UnlockLayer => text_input(app, k.code, |a| {
                let layer = a.input.trim().to_string();
                if layer.parse::<u32>().is_ok() {
                    a.unlock_layer = layer;
                    a.mode = Mode::UnlockPass;
                    a.input.clear();
                    a.status = "type layer passphrase, Enter".into();
                } else {
                    a.status = "layer must be integer".into();
                    a.mode = Mode::List;
                    a.input.clear();
                }
            }),
            Mode::UnlockPass => text_input(app, k.code, |a| {
                let layer = std::mem::take(&mut a.unlock_layer);
                a.run_unlock(layer);
            }),
            Mode::Start => text_input(app, k.code, |a| a.run_start()),
            Mode::Usb => text_input(app, k.code, |a| a.run_usb()),
            Mode::BootstrapPass => text_input(app, k.code, |a| a.bootstrap_push_pass()),
            Mode::HostNet => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.status = HELP.into();
                }
                KeyCode::Char('a') => app.run_host_net("allow"),
                KeyCode::Char('l') => app.run_host_net("lock"),
                KeyCode::Char('t') | KeyCode::Char('s') => app.run_host_net("status"),
                _ => {}
            },
        }
    }
}
