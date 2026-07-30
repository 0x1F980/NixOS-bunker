//! Minimal ratatui app: net + USB + voice + metadata (mat2) defaults in zones.json
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
    Home,
    Net,
    Usb,
    Voice,
    Meta,
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
}

const NET_MODES: &[&str] = &["nym", "i2p", "tor", "none"];

fn bool_flag(z: &Value, key: &str) -> bool {
    match z.get(key) {
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => {
            let s = s.to_lowercase();
            matches!(s.as_str(), "on" | "true" | "1" | "yes" | "anon" | "chimera")
        }
        _ => false,
    }
}

fn voice_on(z: &Value) -> bool {
    bool_flag(z, "voice")
}

fn metadata_on(z: &Value) -> bool {
    bool_flag(z, "metadata")
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
            status: "net + usb + voice + metadata defaults. Edit, then save.".into(),
            dirty: false,
            usb_input: String::new(),
            input_mode: false,
        })
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
        self.status = format!("Saved {}", self.zones_path.display());
        Ok(())
    }

    fn cycle_net(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        let cur = obj
            .get("internet")
            .and_then(|x| x.as_str())
            .unwrap_or("nym");
        let idx = NET_MODES.iter().position(|m| *m == cur).unwrap_or(0);
        let next = NET_MODES[(idx + 1) % NET_MODES.len()];
        obj.insert("internet".into(), json!(next));
        self.dirty = true;
        self.status = format!("{name}: internet → {next}");
    }

    fn toggle_voice(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let on = {
            let z = self.zones.get(&name).unwrap();
            !voice_on(z)
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        obj.insert("voice".into(), json!(on));
        self.dirty = true;
        self.status = format!(
            "{name}: voice → {}  (anonymized mic via voiceVM)",
            if on { "on" } else { "off" }
        );
    }

    fn toggle_metadata(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let on = {
            let z = self.zones.get(&name).unwrap();
            !metadata_on(z)
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        obj.insert("metadata".into(), json!(on));
        self.dirty = true;
        self.status = format!(
            "{name}: metadata → {}  (mat2 EXIF stripper in zone)",
            if on { "on" } else { "off" }
        );
    }

    fn attach_voice_now(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let on = voice_on(self.zones.get(&name).unwrap());
        if on {
            let _ = Command::new("bunker-voice-attach").arg(&name).status();
            self.status = format!("{name}: attached → voiceVM anonymized mic");
        } else {
            let _ = Command::new("bunker-voice-detach").arg(&name).status();
            self.status = format!("{name}: detached (voice off)");
        }
    }

    fn add_usb(&mut self, devid: &str) {
        let devid = devid.trim().to_lowercase();
        if !devid.contains(':') || devid.len() < 5 {
            self.status = "Need vid:pid hex, e.g. 0bda:2838".into();
            return;
        }
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        let arr = obj.entry("usb".to_string()).or_insert_with(|| json!([]));
        let list = arr.as_array_mut().unwrap();
        if list.iter().any(|x| x.as_str() == Some(devid.as_str())) {
            self.status = format!("{name}: {devid} already listed");
            return;
        }
        list.push(json!(devid));
        self.dirty = true;
        self.status = format!("{name}: +usb {devid}");
    }

    fn rm_usb(&mut self) {
        let Some(name) = self.selected_zone().map(|s| s.to_string()) else {
            return;
        };
        let z = self.zones.get_mut(&name).unwrap();
        let obj = z.as_object_mut().unwrap();
        let Some(arr) = obj.get_mut("usb").and_then(|x| x.as_array_mut()) else {
            self.status = format!("{name}: no usb defaults");
            return;
        };
        if arr.is_empty() {
            self.status = format!("{name}: usb list empty");
            return;
        }
        let removed = arr.pop();
        self.dirty = true;
        self.status = format!(
            "{name}: removed {}",
            removed
                .and_then(|v| v.as_str().map(|s| s.to_string()))
                .unwrap_or_default()
        );
    }

    fn start_infra(&mut self, which: &str) {
        self.status = format!("Starting {which}…");
        let _ = Command::new("bunker-zone-start").arg(which).status();
        self.status = format!("bunker-zone-start {which}");
    }
}

fn move_list(app: &mut App, delta: isize) {
    let i = app.list.selected().unwrap_or(0) as isize + delta;
    let n = app.zone_names.len() as isize;
    if n == 0 {
        return;
    }
    let i = ((i % n) + n) % n;
    app.list.select(Some(i as usize));
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
        Screen::Home => "Bunker brokers — net / usb / voice / metadata defaults",
        Screen::Net => "NET defaults — which egress each zone uses",
        Screen::Usb => "USB / I/O defaults — devices auto-attached via usbVM",
        Screen::Voice => "VOICE defaults — anonymized mic on/off per zone",
        Screen::Meta => "META defaults — mat2 EXIF/metadata stripper on/off",
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
        Screen::Home => draw_home(f, chunks[1], app),
        Screen::Net | Screen::Usb | Screen::Voice | Screen::Meta => draw_zones(f, chunks[1], app),
        Screen::Help => draw_help(f, chunks[1]),
    }

    let hint = if app.input_mode {
        format!("USB vid:pid> {}_   Enter=add  Esc=cancel", app.usb_input)
    } else {
        match app.screen {
            Screen::Home => {
                "1 net  2 usb  3 voice  4 meta  n/u/v start  w save  q quit  ?=help".into()
            }
            Screen::Net => {
                "↑↓ zone  Space/Enter cycle nym→i2p→tor→none  w save  Esc home".into()
            }
            Screen::Usb => "↑↓ zone  a add vid:pid  d delete last  w save  Esc home".into(),
            Screen::Voice => {
                "↑↓ zone  Space/Enter toggle on/off  a attach now  w save  Esc home".into()
            }
            Screen::Meta => {
                "↑↓ zone  Space/Enter toggle mat2 on/off  w save  Esc home".into()
            }
            Screen::Help => "Esc back".into(),
        }
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

    if app.input_mode {
        let area = centered(chunks[1], 60, 5);
        f.render_widget(Clear, area);
        f.render_widget(
            Paragraph::new(format!("Attach default USB for zone\n{}", app.usb_input))
                .block(Block::default().borders(Borders::ALL).title("vid:pid")),
            area,
        );
    }
}

fn draw_home(f: &mut Frame, area: Rect, app: &App) {
    let text = vec![
        Line::from("Infrastructure (brokers — one VM, many zones):"),
        Line::from(""),
        Line::from(Span::styled(
            "  netVM  10.0.0.1",
            Style::default().fg(Color::Green).add_modifier(Modifier::BOLD),
        )),
        Line::from("    Sole egress. Zone internet= nym | i2p | tor | none"),
        Line::from(""),
        Line::from(Span::styled(
            "  usbVM  10.0.0.2",
            Style::default()
                .fg(Color::Magenta)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from("    USB 1→many. Zone usb=[\"vid:pid\",…] auto-attach on start"),
        Line::from(""),
        Line::from(Span::styled(
            "  voiceVM  10.0.0.3",
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from("    Mic anonymizer (Chimera/sox). Zone voice= on | off"),
        Line::from(""),
        Line::from(Span::styled(
            "  metadata (mat2)",
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )),
        Line::from("    EXIF/metadata stripper in-zone. Zone metadata= on | off"),
        Line::from(""),
        Line::from(format!("  zones.json: {}", app.zones_path.display())),
        Line::from(format!("  {} app zones loaded", app.zone_names.len())),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("overview")),
        area,
    );
}

fn draw_help(f: &mut Frame, area: Rect) {
    let text = vec![
        Line::from("Net: each zone picks ONE egress via netVM."),
        Line::from("USB: many zones may list a device; live attach = one holder."),
        Line::from("Voice: on = zone uses voiceVM anonymized mic; off = no tunnel."),
        Line::from("Engine (Chimera/sox) runs only on voiceVM — not chosen per zone."),
        Line::from("Meta: on = ship mat2 + bunker-mat into the zone (strip EXIF etc.)."),
        Line::from("ISO/HVM zones ([ISO] tag): net+usb apply; voice/mat2 are NixOS-only."),
        Line::from("CRUD for ISO: zones · service — A/I add ISO, k=kind appvm|disposable|template."),
        Line::from("After save: sudo nixos-rebuild switch --flake .#host (if guests changed)"),
        Line::from("Then: bunker-zone-start <zone>"),
    ];
    f.render_widget(
        Paragraph::new(text).block(Block::default().borders(Borders::ALL).title("help")),
        area,
    );
}

fn draw_zones(f: &mut Frame, area: Rect, app: &mut App) {
    let items: Vec<ListItem> = app
        .zone_names
        .iter()
        .map(|name| {
            let z = &app.zones[name];
            let net = z.get("internet").and_then(|x| x.as_str()).unwrap_or("nym");
            let usb = z
                .get("usb")
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str())
                        .collect::<Vec<_>>()
                        .join(",")
                })
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "-".into());
            let voice = if voice_on(z) { "on" } else { "off" };
            let meta = if metadata_on(z) { "on" } else { "off" };
            let iso = z.get("template").and_then(|x| x.as_str()) == Some("iso")
                || z
                    .get("iso")
                    .and_then(|x| x.as_str())
                    .map(|s| !s.is_empty())
                    .unwrap_or(false);
            let tag = if iso { " [ISO]" } else { "" };
            let line = match app.screen {
                Screen::Net => format!("{name:<12} internet={net}{tag}"),
                Screen::Usb => format!("{name:<12} usb=[{usb}]{tag}"),
                Screen::Voice => format!(
                    "{name:<12} voice={}{tag}",
                    if iso { "n/a" } else { voice }
                ),
                Screen::Meta => format!(
                    "{name:<12} metadata={}{tag}",
                    if iso { "n/a" } else { meta }
                ),
                _ => name.clone(),
            };
            ListItem::new(line)
        })
        .collect();

    let title = match app.screen {
        Screen::Net => "zones → netVM",
        Screen::Usb => "zones → usbVM",
        Screen::Voice => "zones → voiceVM (anonymized mic)",
        Screen::Meta => "zones → mat2 (EXIF / metadata strip)",
        _ => "zones",
    };
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(title))
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut app.list);
}

fn centered(area: Rect, w: u16, h: u16) -> Rect {
    let x = area.x + (area.width.saturating_sub(w)) / 2;
    let y = area.y + (area.height.saturating_sub(h)) / 2;
    Rect::new(x, y, w.min(area.width), h.min(area.height))
}

fn run() -> io::Result<()> {
    let path = env::var("BUNKER_ZONES_JSON")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            [
                PathBuf::from("/etc/bunker/zones.json"),
                PathBuf::from("/home/user/nixos-bunker/config/zones.json"),
                env::current_dir()
                    .unwrap_or_default()
                    .join("config/zones.json"),
            ]
            .into_iter()
            .find(|p| p.exists())
            .unwrap_or_else(|| PathBuf::from("config/zones.json"))
        });

    let path = {
        let home_repo = env::var("HOME")
            .ok()
            .map(|h| PathBuf::from(h).join("nixos-bunker/config/zones.json"));
        if let Some(p) = home_repo {
            if p.exists() {
                p
            } else {
                path
            }
        } else {
            path
        }
    };

    let mut app = App::load(path)?;

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let res = loop_ui(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;
    res
}

fn loop_ui(terminal: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;
        if !event::poll(std::time::Duration::from_millis(200))? {
            continue;
        }
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }

        if app.input_mode {
            match key.code {
                KeyCode::Esc => {
                    app.input_mode = false;
                    app.usb_input.clear();
                }
                KeyCode::Enter => {
                    let s = app.usb_input.clone();
                    app.add_usb(&s);
                    app.usb_input.clear();
                    app.input_mode = false;
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
                KeyCode::Char('q') => break,
                KeyCode::Char('1') => app.screen = Screen::Net,
                KeyCode::Char('2') => app.screen = Screen::Usb,
                KeyCode::Char('3') => app.screen = Screen::Voice,
                KeyCode::Char('4') => app.screen = Screen::Meta,
                KeyCode::Char('n') => app.start_infra("net"),
                KeyCode::Char('u') => app.start_infra("usb"),
                KeyCode::Char('v') => app.start_infra("voice"),
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Char('?') => app.screen = Screen::Help,
                _ => {}
            },
            Screen::Net => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_list(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_list(app, -1),
                KeyCode::Enter | KeyCode::Char(' ') => app.cycle_net(),
                _ => {}
            },
            Screen::Usb => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_list(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_list(app, -1),
                KeyCode::Char('a') => {
                    app.input_mode = true;
                    app.usb_input.clear();
                }
                KeyCode::Char('d') => app.rm_usb(),
                _ => {}
            },
            Screen::Voice => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_list(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_list(app, -1),
                KeyCode::Enter | KeyCode::Char(' ') => app.toggle_voice(),
                KeyCode::Char('a') => app.attach_voice_now(),
                KeyCode::Char('v') => app.start_infra("voice"),
                _ => {}
            },
            Screen::Meta => match key.code {
                KeyCode::Esc => app.screen = Screen::Home,
                KeyCode::Char('q') => break,
                KeyCode::Char('w') => {
                    if let Err(e) = app.save() {
                        app.status = format!("save failed: {e}");
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => move_list(app, 1),
                KeyCode::Up | KeyCode::Char('k') => move_list(app, -1),
                KeyCode::Enter | KeyCode::Char(' ') => app.toggle_metadata(),
                _ => {}
            },
            Screen::Help => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q')) {
                    app.screen = Screen::Home;
                }
            }
        }
    }
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("bunker-broker-tui: {e}");
        std::process::exit(1);
    }
}
