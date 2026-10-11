// Writes one JSON file per Cursor window for Swide, and listens on a Unix
// socket for commands ("close", "ping").
const vscode = require('vscode');
const fs = require('fs');
const net = require('net');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const SUPPORT = path.join(os.homedir(), 'Library', 'Application Support', 'Swide');
const WINDOWS_DIR = path.join(SUPPORT, 'windows');
const SOCKET_DIR = path.join(SUPPORT, 's');

let state;
let file;
let socketPath;
let server;
let timer;

function folders() {
  return (vscode.workspace.workspaceFolders || [])
    .filter((f) => f.uri.scheme === 'file')
    .map((f) => f.uri.fsPath);
}

function write() {
  state.folders = folders();
  const tmp = `${file}.tmp`;
  try {
    fs.writeFileSync(tmp, JSON.stringify(state));
    fs.renameSync(tmp, file);
  } catch (err) {
    console.error('[swide-bridge] write failed', err);
  }
}

function handle(command, conn) {
  switch (command) {
    case 'close':
      conn.end('ok\n');
      vscode.commands.executeCommand('workbench.action.closeWindow');
      break;
    case 'ping':
      conn.end('pong\n');
      break;
    default:
      conn.end('unknown\n');
  }
}

function activate(context) {
  fs.mkdirSync(WINDOWS_DIR, { recursive: true });
  fs.mkdirSync(SOCKET_DIR, { recursive: true });

  // Short id: Unix socket paths are limited to 104 bytes.
  const id = crypto.createHash('sha1').update(`${vscode.env.sessionId}:${process.pid}`).digest('hex').slice(0, 10);
  file = path.join(WINDOWS_DIR, `${id}.json`);
  socketPath = path.join(SOCKET_DIR, `${id}.sock`);

  const focused = vscode.window.state.focused;
  state = { id, pid: process.pid, folders: [], focused, lastFocus: focused ? Date.now() : 0, socket: socketPath };

  try { fs.unlinkSync(socketPath); } catch {}
  server = net.createServer((conn) => {
    conn.setEncoding('utf8');
    let buffer = '';
    conn.on('data', (chunk) => {
      buffer += chunk;
      const newline = buffer.indexOf('\n');
      if (newline >= 0) handle(buffer.slice(0, newline).trim(), conn);
    });
    conn.on('error', () => {});
  });
  server.on('error', (err) => console.error('[swide-bridge] socket error', err));
  server.listen(socketPath);

  context.subscriptions.push(
    // Stamp both gaining and losing focus: the window stays "last used" until then.
    vscode.window.onDidChangeWindowState((s) => {
      if (s.focused !== state.focused) {
        state.focused = s.focused;
        state.lastFocus = Date.now();
        write();
      }
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(write),
  );

  timer = setInterval(write, 30000);
  write();
}

function deactivate() {
  clearInterval(timer);
  try { server && server.close(); } catch {}
  for (const f of [file, socketPath]) {
    try { f && fs.unlinkSync(f); } catch {}
  }
}

module.exports = { activate, deactivate };
