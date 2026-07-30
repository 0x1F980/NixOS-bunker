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
    io::{self, Stdout, Write},
    path::PathBuf,
    process::{Command, Stdio},
};

const NET: &[&str] = &["nym", "i2p", "tor", "none"];
const KIND: &[&str] = &["appvm", "disposable", "template"];
const PANIC: &[&str] = &["keep", "lock", "wipe"];
const COLORS: &[&str] = &[
    "red", "orange", "yellow", "green", "blue", "purple", "black", "gray",
];
const HELP: &str =
    "a add  d del  r rename  c color  t type  n net  i hide  u unlock  l lock  o iso  Space panic  p ARM  w save  q";

#[derive(Clone)]
enum Mode {
    List,
    Panic,
    Add,
    Rename,
    Iso,
    Delete,
    HidePass,
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

fn sha256_hex(s: &str) -> String {
    let out = Command::new("sha256sum")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .and_then(|mut c| {
            if let Some(mut stdin) = c.stdin.take() {
                stdin.write_all(s.as_bytes())?;
            }
            c.wait_with_output()
        });
    out.ok()
        .and_then(|o| {
            String::from_utf8_lossy(&o.stdout)
                .split_whitespace()
                .next()
                .map(|x| x.to_string())
        })
        .unwrap_or_default()
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

    fn next_free_layer(&self) -> u64 {
        let used: Vec<u64> = self
            .zones
            .values()
            .filter_map(|z| {
                if flag(z, "invisible") {
                    z.get("layer").and_then(|v| v.as_u64())
                } else {
                    None
                }
            })
            .collect();
        (1u64..64).find(|n| !used.contains(n)).unwrap_or(1)
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
        if on {
            let layer = self.next_free_layer();
            let z = self.zones.entry(n.clone()).or_insert(json!({}));
            let o = z.as_object_mut().unwrap();
            o.insert("invisible".into(), json!(true));
            o.insert("layer".into(), json!(layer));
            self.dirty = true;
            self.mode = Mode::HidePass;
            self.input.clear();
            self.status = format!("{n}: hide ON unique layer={layer} — set passphrase");
        } else {
            let z = self.zones.entry(n.clone()).or_insert(json!({}));
            let o = z.as_object_mut().unwrap();
            o.insert("invisible".into(), json!(false));
            o.insert("layer".into(), Value::Null);
            o.remove("hideHash");
            self.dirty = true;
            self.status = format!("{n}: hide OFF");
        }
    }

    fn set_hide_pass(&mut self, pass: &str) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        if pass.is_empty() {
            self.status = "empty passphrase skipped — press u later".into();
            return;
        }
        let hash = sha256_hex(pass);
        if let Some(z) = self.zones.get_mut(&n) {
            if let Some(o) = z.as_object_mut() {
                o.insert("hideHash".into(), json!(hash));
                self.dirty = true;
                self.status = format!("{n}: unique hide passphrase set");
            }
        }
    }

    fn unlock_zone(&mut self, pass: &str) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        let Some(z) = self.zones.get(&n) else {
            return;
        };
        if !flag(z, "invisible") {
            self.status = "not hidden".into();
            return;
        }
        if let Some(h) = z.get("hideHash").and_then(|v| v.as_str()) {
            if !h.is_empty() && sha256_hex(pass) != h {
                self.status = "denied (wrong passphrase for this zone)".into();
                return;
            }
        }
        match Command::new("bunker-sflc")
            .args(["unlock-zone", &n])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(mut c) => {
                if let Some(mut stdin) = c.stdin.take() {
                    let _ = writeln!(stdin, "{pass}");
                }
                match c.wait_with_output() {
                    Ok(o) if o.status.success() => {
                        self.status = format!("{n}: unlocked (only this zone)")
                    }
                    Ok(o) => {
                        self.status = format!(
                            "unlock fail: {}",
                            String::from_utf8_lossy(&o.stderr).trim()
                        )
                    }
                    Err(e) => self.status = format!("unlock: {e}"),
                }
            }
            Err(e) => self.status = format!("bunker-sflc: {e}"),
        }
    }

    fn lock_zone(&mut self) {
        let Some(n) = self.sel().map(str::to_string) else {
            return;
        };
        if !flag(&self.zones[&n], "invisible") {
            self.status = "not hidden".into();
            return;
        }
        match Command::new("bunker-sflc").args(["lock-zone", &n]).output() {
            Ok(o) if o.status.success() => self.status = format!("{n}: locked"),
            Ok(o) => {
                self.status = format!("lock: {}", String::from_utf8_lossy(&o.stderr).trim())
            }
            Err(e) => self.status = format!("lock: {e}"),
        }
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
        Mode::HidePass => {
            let cur = app.sel().unwrap_or("?");
            f.render_widget(
                Paragraph::new(format!(
                    "Hide passphrase for '{cur}' (UNIQUE per zone): {}*",
                    "*".repeat(app.input.len())
                ))
                .block(Block::default().borders(Borders::ALL).title("HIDE passphrase")),
                c[0],
            );
        }
        Mode::UnlockPass => {
            let cur = app.sel().unwrap_or("?");
            f.render_widget(
                Paragraph::new(format!(
                    "Unlock ONLY '{cur}': {}*",
                    "*".repeat(app.input.len())
                ))
                .block(Block::default().borders(Borders::ALL).title("UNLOCK zone")),
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
                    let layer = z.get("layer").and_then(|v| v.as_u64());
                    let hide = if flag(z, "invisible") {
                        format!("L{}", layer.unwrap_or(0))
                    } else {
                        "-".into()
                    };
                    ListItem::new(format!(
                        "{n:<12} {kind:<11} {color:<7} net={net:<4} hide={hide:<3} panic={panic}{iso}",
                        kind = kind_of(z),
                        color = z.get("color").and_then(|x| x.as_str()).unwrap_or("gray"),
                        net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("nym"),
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
                KeyCode::Char('u') => {
                    if let Some(n) = app.sel().map(str::to_string) {
                        if flag(&app.zones[&n], "invisible") {
                            let has = app.zones[&n]
                                .get("hideHash")
                                .and_then(|v| v.as_str())
                                .is_some_and(|s| !s.is_empty());
                            app.input.clear();
                            if has {
                                app.mode = Mode::UnlockPass;
                                app.status = "passphrase for THIS zone only".into();
                            } else {
                                app.mode = Mode::HidePass;
                                app.status = "set unique hide passphrase first".into();
                            }
                        } else {
                            app.status = "select a hidden zone (or press i)".into();
                        }
                    }
                }
                KeyCode::Char('l') => app.lock_zone(),
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
            Mode::HidePass => match k.code {
                KeyCode::Esc => {
                    app.mode = Mode::List;
                    app.input.clear();
                    app.status = HELP.into();
                }
                KeyCode::Enter => {
                    let pass = app.input.clone();
                    app.mode = Mode::List;
                    app.input.clear();
                    app.set_hide_pass(&pass);
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
                    let pass = app.input.clone();
                    app.mode = Mode::List;
                    app.input.clear();
                    app.unlock_zone(&pass);
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
