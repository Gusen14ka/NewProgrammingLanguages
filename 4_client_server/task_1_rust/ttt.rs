use std::env;
use std::io::{self, BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::process;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

const LINES: [[usize; 3]; 8] = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
];

fn send(stream: &mut TcpStream, msg: &str) {
    let _ = writeln!(stream, "{}", msg);
}

fn board_text(board: &[char; 9]) -> String {
    let cell = |i: usize| if board[i] == ' ' { char::from(b'1' + i as u8) } else { board[i] };
    (0..3)
        .map(|r| format!(" {} | {} | {}", cell(r * 3), cell(r * 3 + 1), cell(r * 3 + 2)))
        .collect::<Vec<_>>()
        .join("\n---+---+---\n")
}

fn winner(board: &[char; 9]) -> Option<char> {
    LINES.iter().find_map(|l| {
        let c = board[l[0]];
        if c != ' ' && c == board[l[1]] && c == board[l[2]] { Some(c) } else { None }
    })
}

fn play(id: usize, mut players: [TcpStream; 2]) {
    let marks = ['X', 'O'];
    let mut readers: Vec<BufReader<TcpStream>> = players
        .iter()
        .map(|p| BufReader::new(p.try_clone().expect("clone")))
        .collect();
    let mut board = [' '; 9];
    println!("[game {}] started", id);

    for i in 0..2 {
        send(&mut players[i], &format!("Game #{} started. You play {}.", id, marks[i]));
    }

    let mut turn = 0;
    loop {
        let (cur, other) = (turn % 2, (turn + 1) % 2);
        let text = board_text(&board);
        for p in players.iter_mut() {
            send(p, &format!("\n{}\n", text));
        }
        send(&mut players[other], &format!("Waiting for {}...", marks[cur]));

        let cell = loop {
            send(&mut players[cur], "Your move (1-9):");
            let mut line = String::new();
            if readers[cur].read_line(&mut line).unwrap_or(0) == 0 {
                println!("[game {}] player {} disconnected", id, marks[cur]);
                send(&mut players[other], "Opponent disconnected. You win!");
                return;
            }
            match line.trim().parse::<usize>() {
                Ok(n) if (1..=9).contains(&n) && board[n - 1] == ' ' => break n - 1,
                _ => send(&mut players[cur], "Invalid move, try again."),
            }
        };

        board[cell] = marks[cur];
        println!("[game {}] {} -> {}", id, marks[cur], cell + 1);

        let result = if let Some(w) = winner(&board) {
            Some(format!("{} wins!", w))
        } else if board.iter().all(|&c| c != ' ') {
            Some("Draw!".to_string())
        } else {
            None
        };

        if let Some(msg) = result {
            let text = board_text(&board);
            for p in players.iter_mut() {
                send(p, &format!("\n{}\n\nGame over: {}", text, msg));
            }
            println!("[game {}] finished: {}", id, msg);
            return;
        }
        turn += 1;
    }
}

fn run_server(port: &str) {
    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).expect("bind");
    println!("Server listening on port {}", port);
    let waiting: Arc<Mutex<Option<TcpStream>>> = Arc::new(Mutex::new(None));
    let games = Arc::new(AtomicUsize::new(0));

    for stream in listener.incoming().flatten() {
        let waiting = Arc::clone(&waiting);
        let games = Arc::clone(&games);
        thread::spawn(move || {
            let mut stream = stream;
            println!("Client connected: {}", stream.peer_addr().map(|a| a.to_string()).unwrap_or_default());
            let mut slot = waiting.lock().unwrap();
            match slot.take() {
                Some(first) => {
                    drop(slot);
                    let id = games.fetch_add(1, Ordering::SeqCst) + 1;
                    play(id, [first, stream]);
                }
                None => {
                    send(&mut stream, "Waiting for an opponent...");
                    *slot = Some(stream);
                }
            }
        });
    }
}

fn run_client(addr: &str) {
    let stream = TcpStream::connect(addr).unwrap_or_else(|e| {
        eprintln!("Cannot connect to {}: {}", addr, e);
        process::exit(1);
    });
    let reader = BufReader::new(stream.try_clone().expect("clone"));
    thread::spawn(move || {
        for line in reader.lines().flatten() {
            println!("{}", line);
        }
        println!("Connection closed.");
        process::exit(0);
    });
    let mut writer = stream;
    for line in io::stdin().lock().lines().flatten() {
        if writeln!(writer, "{}", line).is_err() {
            break;
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("server") => run_server(args.get(2).map(String::as_str).unwrap_or("7878")),
        Some("client") => run_client(args.get(2).map(String::as_str).unwrap_or("127.0.0.1:7878")),
        _ => eprintln!("Usage: ttt server [port] | ttt client [host:port]"),
    }
}
