//! bunker — simple full zone CRUD (ratatui).
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
    io::{self, Stdout},
    path::PathBuf,
    process::Command,
};

const NET: &[&str] = &["nym", "i2p", "tor", "none"];
const KIND: &[&str] = &["appvm", "disposable", "template"];
const PANIC: &[&str] = &["keep", "lock", "wipe"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const HELP: &str =
    "a add  d del  r rename  c color  t type  n net  i hide  u unlock  o iso  f file  Space panic  p ARM  w save  q quit";

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

impl App {
    fn load(path: PathBuf) -> io::Result<Self> {
        let v: Value = serde_json::from_str(&fs::read_to_string(&path)?)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let zones = v
            .as_object()
            .cloned()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "bad zones.json"))?;
        let mut app = Self {
            path,
            zones,
            names: vec![],
            list: ListState::default(),
            status: HELP.into(),
            dirty: false,
            mode: Mode::List,
            input: String::new(),
            unlock_layer: String::new(),
        };
        app.refresh_names();
        Ok(app)
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
        self.list.selected().map(|i| self.names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let s = serde_json::to_string_pretty(&Value::Object(self.zones.clone()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let _ = fs::copy(&self.path, self.path.with_extension("json.bak"));
        fs::write(&self.path, s)?;
        self.dirty = false;
        self.status = format!("saved — rebuild icons: sudo nixos-rebuild switch --flake .#host");
        Ok(())
    }

    fn alloc(&self) -> (String, String, u64) {
        let mut used_ip = vec![];
        let mut used_socks = vec![];
        let mut used_mac = vec![];
        for c in self.zones.values() {
            if let Some(ip) = c.get("ip").and_then(|x| x.as_str()) {
                if let Some(last) = ip.split('.').next_back() {
                    if let Ok(n) = last.parse::<u8>() {
                        used_ip.push(n);
                    }
                }
            }
            if let Some(s) = c.get("socks").and_then(|x| x.as_u64()) {
                used_socks.push(s);
            }
            if let Some(mac) = c.get("mac").and_then(|x| x.as_str()) {
                if let Some(last) = mac.split(':').next_back() {
                    if let Ok(n) = u8::from_str_radix(last, 16) {
                        used_mac.push(n);
                    }
                }
            }
        }
        let ipn = (11u8..250).find(|i| !used_ip.contains(i)).unwrap_or(11);
        let macn = (0x11u8..0xfe).find(|i| !used_mac.contains(i)).unwrap_or(0x11);
        let socks = (1081u64..1200)
            .find(|p| !used_socks.contains(p))
            .unwrap_or(1081);
        (
            format!("10.0.0.{ipn}"),
            format!("02:b0:00:00:00:{macn:02x}"),
            socks,
        )
    }

    fn cycle(&mut self, key: &str, modes: &[&str]) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(n.clone()).or_insert(json!({}));
        let o = z.as_object_mut().unwrap();
        let cur = o.get(key).and_then(|x| x.as_str()).unwrap_or(modes[0]);
        let i = modes.iter().position(|m| *m == cur).unwrap_or(0);
        let next = modes[(i + 1) % modes.len()];
        o.insert(key.into(), json!(next));
        self.dirty = true;
        self.status = format!("{n}: {key} → {next}");
    }

    fn cycle_kind(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let cur = kind_of(&self.zones[&n]);
        let i = KIND.iter().position(|m| *m == cur).unwrap_or(0);
        let next = KIND[(i + 1) % KIND.len()];
        let z = self.zones.entry(n.clone()).or_insert(json!({}));
        let o = z.as_object_mut().unwrap();
        o.insert("kind".into(), json!(next));
        o.insert("disposable".into(), json!(next == "disposable"));
        self.dirty = true;
        self.status = format!("{n}: type → {next}");
    }

    fn cycle_color(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(n.clone()).or_insert(json!({}));
        let o = z.as_object_mut().unwrap();
        let cur = o.get("color").and_then(|x| x.as_str()).unwrap_or("gray");
        let i = COLORS.iter().position(|m| *m == cur).unwrap_or(0);
        let next = COLORS[(i + 1) % COLORS.len()];
        o.insert("color".into(), json!(next));
        self.dirty = true;
        self.status = format!("{n}: color → {next} (icon + terminal)");
    }

    fn toggle_invisible(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let on = !flag(&self.zones[&n], "invisible");
        let z = self.zones.entry(n.clone()).or_insert(json!({}));
        let o = z.as_object_mut().unwrap();
        o.insert("invisible".into(), json!(on));
        o.insert("layer".into(), if on { json!(1) } else { Value::Null });
        self.dirty = true;
        self.status = format!(
            "{n}: hidden → {}",
            if on { "yes (unlock: bunker-sflc)" } else { "no" }
        );
    }

    fn add_zone(&mut self, name: String) {
        if !valid_name(&name) {
            self.status = "name: letters, numbers, - _ only".into();
            return;
        }
        if self.zones.contains_key(&name) {
            self.status = format!("exists: {name}");
            return;
        }
        let (ip, mac, socks) = self.alloc();
        self.zones.insert(
            name.clone(),
            json!({
                "template": "browser",
                "kind": "appvm",
                "ip": ip,
                "mac": mac,
                "socks": socks,
                "mem": 1536,
                "diskGb": 16,
                "vcpu": 2,
                "disposable": false,
                "color": "red",
                "internet": "nym",
                "usb": [],
                "apps": [],
                "invisible": false,
                "layer": null,
                "panic": "keep"
            }),
        );
        self.refresh_names();
        if let Some(i) = self.names.iter().position(|n| n == &name) {
            self.list.select(Some(i));
        }
        self.dirty = true;
        self.status = format!("added {name} — set type/color/net, then w save");
    }

    fn rename_zone(&mut self, new: String) {
        let Some(old) = self.sel().map(str::to_string) else {
            return;
        };
        if !valid_name(&new) {
            self.status = "name: letters, numbers, - _ only".into();
            return;
        }
        if self.zones.contains_key(&new) {
            self.status = format!("exists: {new}");
            return;
        }
        if let Some(z) = self.zones.remove(&old) {
            self.zones.insert(new.clone(), z);
            self.refresh_names();
            if let Some(i) = self.names.iter().position(|n| n == &new) {
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
        let z = self.zones.entry(n.clone()).or_insert(json!({}));
        let o = z.as_object_mut().unwrap();
        if path.is_empty() {
            o.remove("iso");
            if o.get("template").and_then(|x| x.as_str()) == Some("iso") {
                o.insert("template".into(), json!("browser"));
            }
            self.status = format!("{n}: ISO cleared");
        } else {
            o.insert("template".into(), json!("iso"));
            o.insert("iso".into(), json!(path.clone()));
            o.insert("boot".into(), json!("iso"));
            o.insert("display".into(), json!("gtk"));
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
        match Command::new("bunker-panic")
            .arg("--yes")
            .env("BUNKER_PANIC_PASS", pass)
            .output()
        {
            Ok(o) if o.status.success() => self.status = "panic OK — reboot".into(),
            Ok(o) => self.status = format!("panic: {}", String::from_utf8_lossy(&o.stderr).trim()),
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
        match Command::new("bunker-file")
            .args(["copy", parts[0], parts[1]])
            .output()
        {
            Ok(o) if o.status.success() => {
                self.status = format!("OK file {}", String::from_utf8_lossy(&o.stdout).trim())
            }
            Ok(o) => {
                self.status = format!(
                    "file: {}",
                    String::from_utf8_lossy(&o.stderr)
                        .trim()
                        .chars()
                        .take(120)
                        .collect::<String>()
                )
            }
            Err(e) => self.status = format!("file: {e}"),
        }
    }

    fn run_unlock(&mut self, layer: String) {
        let pass = std::mem::take(&mut self.input);
        self.mode = Mode::List;
        match Command::new("bunker-sflc")
            .args(["unlock", &layer])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut c| {
                use std::io::Write;
                if let Some(mut stdin) = c.stdin.take() {
                    writeln!(stdin, "{pass}")?;
                }
                c.wait_with_output()
            }) {
            Ok(o) if o.status.success() => {
                self.status = format!("unlocked L{layer}");
            }
            Ok(o) => {
                let err = String::from_utf8_lossy(&o.stderr);
                let out = String::from_utf8_lossy(&o.stdout);
                self.status = format!(
                    "unlock: {}",
                    err.trim()
                        .chars()
                        .chain(out.trim().chars())
                        .take(120)
                        .collect::<String>()
                );
            }
            Err(e) => self.status = format!("unlock: {e}"),
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
                    "copy srcZone:/path dstZone:/path\n{}_",
                    app.input
                ))
                .block(Block::default().borders(Borders::ALL).title("FILE COPY")),
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
                        hide = if flag(z, "invisible") { "yes" } else { "-" },
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
                            .title("bunker · zones"),
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
                    app.status = "file copy: srcZone:/path dstZone:/path".into();
                }
                KeyCode::Char('u') => {
                    app.mode = Mode::UnlockLayer;
                    app.input.clear();
                    app.status = "sflc unlock: layer number".into();
                }
                _ => {}
            },
            Mode::Panic => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => app.run_panic(),
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
            Mode::Add => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let name = app.input.trim().to_string();
                    app.mode = Mode::List;
                    app.input.clear();
                    app.add_zone(name);
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
            Mode::Rename => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let name = app.input.trim().to_string();
                    app.mode = Mode::List;
                    app.input.clear();
                    app.rename_zone(name);
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
            Mode::Iso => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let path = app.input.trim().to_string();
                    app.mode = Mode::List;
                    app.input.clear();
                    app.set_iso(path);
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
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
            Mode::FileCopy => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => app.run_file_copy(),
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
            Mode::UnlockLayer => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let layer = app.input.trim().to_string();
                    if layer.parse::<u32>().is_ok() {
                        app.unlock_layer = layer;
                        app.mode = Mode::UnlockPass;
                        app.input.clear();
                        app.status = "type layer passphrase, Enter".into();
                    } else {
                        app.status = "layer must be integer".into();
                        app.mode = Mode::List;
                        app.input.clear();
                    }
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
            Mode::UnlockPass => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let layer = std::mem::take(&mut app.unlock_layer);
                    app.run_unlock(layer);
                }
                KeyCode::Backspace => {
                    app.input.pop();
                }
                KeyCode::Char(ch) => app.input.push(ch),
                _ => {}
            },
        }
    }
}
