//! Single host operator TUI: brokers + zones (invisible/panic) + panic action.
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::Line,
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

#[derive(Clone, Copy, PartialEq, Eq)]
enum Screen {
    Home,
    Net,
    Usb,
    Voice,
    Meta,
    Zones,
    Panic,
    Help,
}

struct App {
    zones_path: PathBuf,
    zones: Map<String, Value>,
    screen: Screen,
    zone_names: Vec<String>,
    list: ListState,
    status: String,
    dirty: bool,
    usb_input: String,
    input_mode: bool,
    panic_input: String,
    panic_mode: bool,
}

const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];
const PANIC_MODES: &[&str] = &["keep", "lock", "wipe"];

fn bool_flag(z: &Value, key: &str) -> bool {
    match z.get(key) {
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => {
            let s = s.to_lowercase();
            matches!(s.as_str(), "on" | "true" | "1" | "yes")
        }
        _ => false,
    }
}

fn panic_mode(z: &Value) -> &str {
    z.get("panic")
        .and_then(|v| v.as_str())
        .filter(|s| PANIC_MODES.contains(s))
        .unwrap_or("keep")
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
            screen: Screen::Home,
            zone_names,
            list,
            status: "bunker — 1 brokers  2 zones  3 panic  ? help  q quit".into(),
            dirty: false,
            usb_input: String::new(),
            input_mode: false,
            panic_input: String::new(),
            panic_mode: false,
        })
    }

    fn selected(&self) -> Option<&str> {
        self.list.selected().map(|i| self.zone_names[i].as_str())
    }

    fn save(&mut self) -> io::Result<()> {
        let pretty = serde_json::to_string_pretty(&Value::Object(self.zones.clone()))
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let bak = self.zones_path.with_extension("json.bak");
        let _ = fs::copy(&self.zones_path, &bak);
        fs::write(&self.zones_path, pretty)?;
        self.dirty = false;
        self.status = format!("saved {}", self.zones_path.display());
        Ok(())
    }

    fn cycle_net(&mut self) {
        let Some(name) = self.selected().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(name.clone()).or_insert(json!({}));
        let obj = z.as_object_mut().unwrap();
        let cur = obj
            .get("internet")
            .and_then(|x| x.as_str())
            .unwrap_or("nym");
        let i = NET_MODES.iter().position(|m| *m == cur).unwrap_or(0);
        let next = NET_MODES[(i + 1) % NET_MODES.len()];
        obj.insert("internet".into(), json!(next));
        self.dirty = true;
        self.status = format!("{name}: internet → {next}");
    }

    fn toggle_bool(&mut self, key: &str) {
        let Some(name) = self.selected().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(name.clone()).or_insert(json!({}));
        let obj = z.as_object_mut().unwrap();
        let on = !bool_flag(z, key);
        obj.insert(key.into(), json!(on));
        self.dirty = true;
        self.status = format!("{name}: {key} → {}", if on { "on" } else { "off" });
    }

    fn cycle_panic(&mut self) {
        let Some(name) = self.selected().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(name.clone()).or_insert(json!({}));
        let obj = z.as_object_mut().unwrap();
        let cur = panic_mode(z);
        let i = PANIC_MODES.iter().position(|m| *m == cur).unwrap_or(0);
        let next = PANIC_MODES[(i + 1) % PANIC_MODES.len()];
        obj.insert("panic".into(), json!(next));
        self.dirty = true;
        self.status = format!("{name}: panic → {next}");
    }

    fn toggle_invisible(&mut self) {
        let Some(name) = self.selected().map(str::to_string) else {
            return;
        };
        let z = self.zones.entry(name.clone()).or_insert(json!({}));
        let obj = z.as_object_mut().unwrap();
        let on = !bool_flag(z, "invisible");
        obj.insert("invisible".into(), json!(on));
        if on && obj.get("layer").and_then(|v| v.as_u64()).is_none() {
            obj.insert("layer".into(), json!(1));
        }
        if !on {
            obj.insert("layer".into(), Value::Null);
        }
        self.dirty = true;
        self.status = format!(
            "{name}: invisible → {}{}",
            if on { "on" } else { "off" },
            if on { " layer=1" } else { "" }
        );
    }

    fn run_panic(&mut self) {
        let pass = self.panic_input.clone();
        self.panic_input.clear();
        self.panic_mode = false;
        let out = Command::new("bunker-panic")
            .arg("--yes")
            .env("BUNKER_PANIC_PASS", pass)
            .output();
        match out {
            Ok(o) if o.status.success() => self.status = "panic OK — reboot recommended".into(),
            Ok(o) => {
                self.status = format!(
                    "panic failed: {}",
                    String::from_utf8_lossy(&o.stderr).trim()
                )
            }
            Err(e) => self.status = format!("panic exec: {e}"),
        }
    }
}

fn draw(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(f.area());

    let title = match app.screen {
        Screen::Home => "bunker",
        Screen::Net => "brokers · net",
        Screen::Usb => "brokers · devices",
        Screen::Voice => "brokers · voice",
        Screen::Meta => "brokers · metadata",
        Screen::Zones => "zones",
        Screen::Panic => "panic",
        Screen::Help => "help",
    };
    f.render_widget(
        Paragraph::new(title).block(Block::default().borders(Borders::ALL).title("bunker")),
        chunks[0],
    );

    match app.screen {
        Screen::Home => {
            let items = [
                "1  Brokers (net / devices / voice / metadata)",
                "2  Zones (apps · mem · invisible · panic flags)",
                "3  Panic (enter code → wipe/lock per zone flags)",
                "?  Help     q  Quit",
            ];
            let list: Vec<ListItem> = items.iter().map(|s| ListItem::new(*s)).collect();
            f.render_widget(
                List::new(list).block(Block::default().borders(Borders::ALL).title("home")),
                chunks[1],
            );
        }
        Screen::Help => {
            let t = "\
Zone model (minimal):\n\
  apps[] on zone · mem/diskGb on zone only\n\
  invisible+layer+password per Shufflecake layer\n\
  panic keep|lock|wipe per zone\n\
Brokers always visible (net/usb/voice).\n\
Keys: w save · Space cycle/toggle · Esc home · q quit";
            f.render_widget(
                Paragraph::new(t).block(Block::default().borders(Borders::ALL)),
                chunks[1],
            );
        }
        Screen::Panic => {
            let hint = if app.panic_mode {
                format!("code: {}_", app.panic_input)
            } else {
                "Enter = type panic code · Esc cancel".into()
            };
            f.render_widget(
                Paragraph::new(hint).block(Block::default().borders(Borders::ALL).title("☢")),
                chunks[1],
            );
        }
        _ => {
            let items: Vec<ListItem> = app
                .zone_names
                .iter()
                .map(|name| {
                    let z = &app.zones[name];
                    let net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("nym");
                    let mem = z.get("mem").and_then(|x| x.as_u64()).unwrap_or(0);
                    let inv = if bool_flag(z, "invisible") {
                        "inv"
                    } else {
                        "-"
                    };
                    let line = match app.screen {
                        Screen::Net => format!("{name:<12} internet={net}"),
                        Screen::Usb => {
                            let usb = z
                                .get("usb")
                                .and_then(|u| u.as_array())
                                .map(|a| {
                                    a.iter()
                                        .filter_map(|x| x.as_str())
                                        .collect::<Vec<_>>()
                                        .join(",")
                                })
                                .unwrap_or_default();
                            format!("{name:<12} usb=[{usb}]")
                        }
                        Screen::Voice => format!(
                            "{name:<12} voice={}",
                            if bool_flag(z, "voice") { "on" } else { "off" }
                        ),
                        Screen::Meta => format!(
                            "{name:<12} metadata={}",
                            if bool_flag(z, "metadata") {
                                "on"
                            } else {
                                "off"
                            }
                        ),
                        Screen::Zones => format!(
                            "{name:<12} mem={mem} {inv} panic={}",
                            panic_mode(z)
                        ),
                        _ => name.clone(),
                    };
                    ListItem::new(line)
                })
                .collect();
            let mut state = app.list.clone();
            f.render_stateful_widget(
                List::new(items)
                    .block(Block::default().borders(Borders::ALL).title("zones"))
                    .highlight_style(Style::default().add_modifier(Modifier::BOLD).fg(Color::Cyan)),
                chunks[1],
                &mut state,
            );
        }
    }

    let footer = if app.dirty {
        format!("{}  [unsaved]", app.status)
    } else {
        app.status.clone()
    };
    f.render_widget(
        Paragraph::new(Line::from(footer)).block(Block::default().borders(Borders::ALL)),
        chunks[2],
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
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "zones.json not found"))?;

    let mut app = App::load(path)?;
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;

    let res = run(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    res
}

fn run(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|f| draw(f, app))?;
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }

        if app.panic_mode {
            match key.code {
                KeyCode::Esc => {
                    app.panic_mode = false;
                    app.panic_input.clear();
                    app.screen = Screen::Home;
                }
                KeyCode::Enter => app.run_panic(),
                KeyCode::Backspace => {
                    app.panic_input.pop();
                }
                KeyCode::Char(c) => app.panic_input.push(c),
                _ => {}
            }
            continue;
        }

        if app.input_mode {
            match key.code {
                KeyCode::Esc => {
                    app.input_mode = false;
                    app.usb_input.clear();
                }
                KeyCode::Enter => {
                    if let Some(name) = app.selected().map(str::to_string) {
                        let z = app.zones.entry(name).or_insert(json!({}));
                        let obj = z.as_object_mut().unwrap();
                        let mut arr = obj
                            .get("usb")
                            .and_then(|u| u.as_array())
                            .cloned()
                            .unwrap_or_default();
                        if !app.usb_input.is_empty() {
                            arr.push(json!(app.usb_input.clone()));
                            obj.insert("usb".into(), Value::Array(arr));
                            app.dirty = true;
                        }
                    }
                    app.input_mode = false;
                    app.usb_input.clear();
                }
                KeyCode::Backspace => {
                    app.usb_input.pop();
                }
                KeyCode::Char(c) => app.usb_input.push(c),
                _ => {}
            }
            continue;
        }

        match app.screen {
            Screen::Home => match key.code {
                KeyCode::Char('q') => return Ok(()),
                KeyCode::Char('1') => app.screen = Screen::Net,
                KeyCode::Char('2') => app.screen = Screen::Zones,
                KeyCode::Char('3') => app.screen = Screen::Panic,
                KeyCode::Char('?') => app.screen = Screen::Help,
                _ => {}
            },
            Screen::Help => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q')) {
                    app.screen = Screen::Home;
                }
            }
            Screen::Panic => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Enter => {
                    app.panic_mode = true;
                    app.status = "type panic passphrase, Enter to arm".into();
                }
                _ => {}
            },
            Screen::Net | Screen::Usb | Screen::Voice | Screen::Meta | Screen::Zones => {
                match key.code {
                    KeyCode::Esc => app.screen = Screen::Home,
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Char('w') => {
                        if let Err(e) = app.save() {
                            app.status = format!("save error: {e}");
                        }
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        let i = app.list.selected().unwrap_or(0);
                        let n = app.zone_names.len().saturating_sub(1);
                        app.list.select(Some((i + 1).min(n)));
                    }
                    KeyCode::Up | KeyCode::Char('k') => {
                        let i = app.list.selected().unwrap_or(0);
                        app.list.select(Some(i.saturating_sub(1)));
                    }
                    KeyCode::Char('1') if app.screen != Screen::Zones => app.screen = Screen::Net,
                    KeyCode::Char('2') if matches!(app.screen, Screen::Net | Screen::Usb | Screen::Voice | Screen::Meta) => {
                        app.screen = Screen::Usb
                    }
                    KeyCode::Char('3')
                        if matches!(app.screen, Screen::Net | Screen::Usb | Screen::Voice | Screen::Meta) =>
                    {
                        app.screen = Screen::Voice
                    }
                    KeyCode::Char('4')
                        if matches!(app.screen, Screen::Net | Screen::Usb | Screen::Voice | Screen::Meta) =>
                    {
                        app.screen = Screen::Meta
                    }
                    KeyCode::Char(' ') | KeyCode::Enter => match app.screen {
                        Screen::Net => app.cycle_net(),
                        Screen::Voice => app.toggle_bool("voice"),
                        Screen::Meta => app.toggle_bool("metadata"),
                        Screen::Zones => app.cycle_panic(),
                        Screen::Usb => {
                            app.input_mode = true;
                            app.status = "vid:pid then Enter".into();
                        }
                        _ => {}
                    },
                    KeyCode::Char('i') if app.screen == Screen::Zones => app.toggle_invisible(),
                    KeyCode::Char('d') if app.screen == Screen::Usb => {
                        if let Some(name) = app.selected().map(str::to_string) {
                            if let Some(z) = app.zones.get_mut(&name) {
                                if let Some(obj) = z.as_object_mut() {
                                    if let Some(Value::Array(arr)) = obj.get_mut("usb") {
                                        arr.pop();
                                        app.dirty = true;
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}
