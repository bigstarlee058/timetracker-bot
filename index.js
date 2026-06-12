import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import robot from 'robotjs';

const watcherScriptPath = join(
  dirname(fileURLToPath(import.meta.url)),
  'watch-user-input.ps1',
);

let step = 0;
let intervalId;
let inputWatcher;
let stopped = false;
const pressedModifiers = new Set();

function keyDown(key) {
  robot.keyToggle(key, 'down');
  pressedModifiers.add(key);
}

function keyUp(key) {
  robot.keyToggle(key, 'up');
  pressedModifiers.delete(key);
}

function releasePressedModifiers() {
  for (const key of pressedModifiers) {
    try {
      robot.keyToggle(key, 'up');
    } catch (error) {
      process.stderr.write(`Failed to release ${key}: ${error.message}\n`);
    }
  }

  pressedModifiers.clear();
}

function stopBot(reason) {
  if (stopped) {
    return;
  }

  stopped = true;

  if (intervalId) {
    clearInterval(intervalId);
  }

  releasePressedModifiers();

  if (inputWatcher && !inputWatcher.killed) {
    inputWatcher.kill();
  }

  process.stdout.write(`Stopped: ${reason}.\n`);
  process.exit(0);
}

function performAutomationStep() {
  if (Math.trunc(step / 60) % 3 === 2 && step % 60 === 0) {
    const rand = Math.trunc(Math.random() * 10000) % 10;
    keyDown('alt');
    for (let j = 0; j < rand; j += 1) {
      robot.keyTap('tab');
    }
    keyUp('alt');
  } else if (step % 60 === 0) {
    const rand = Math.trunc(Math.random() * 10000) % 10;
    keyDown('control');
    for (let j = 0; j < rand; j += 1) {
      robot.keyTap('tab');
    }
    keyUp('control');
  } else if (step % 10 < 5) {
    robot.keyTap('up');
  } else {
    robot.keyTap('down');
  }

  if (step % 7 === 0) {
    robot.scrollMouse(50, 0);
  }

  step += 1;
}

function handleWatcherLine(line, markReady) {
  if (line === 'ready') {
    markReady();
    return;
  }

  if (line === 'keyboard' || line === 'mouse') {
    stopBot(`physical ${line} input detected`);
  }
}

function startUserInputWatcher() {
  if (process.platform !== 'win32') {
    throw new Error('Physical input stop detection is currently implemented for Windows only.');
  }

  inputWatcher = spawn(
    'powershell.exe',
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', watcherScriptPath],
    {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    },
  );

  let ready = false;
  let stdoutBuffer = '';
  let stderrBuffer = '';
  let resolveReady;
  let rejectReady;

  const readyPromise = new Promise((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });

  const markReady = () => {
    if (!ready) {
      ready = true;
      resolveReady();
    }
  };

  inputWatcher.stdout.setEncoding('utf8');
  inputWatcher.stdout.on('data', (chunk) => {
    stdoutBuffer += chunk;
    const lines = stdoutBuffer.split(/\r?\n/);
    stdoutBuffer = lines.pop() ?? '';

    for (const line of lines) {
      handleWatcherLine(line.trim(), markReady);
    }
  });

  inputWatcher.stderr.setEncoding('utf8');
  inputWatcher.stderr.on('data', (chunk) => {
    stderrBuffer += chunk;
    if (ready) {
      process.stderr.write(chunk);
    }
  });

  inputWatcher.on('error', (error) => {
    if (!ready) {
      rejectReady(error);
      return;
    }

    stopBot(`input watcher error: ${error.message}`);
  });

  inputWatcher.on('exit', (code, signal) => {
    if (stopped) {
      return;
    }

    if (!ready) {
      const details = stderrBuffer.trim() || `exit code ${code ?? 'unknown'}, signal ${signal ?? 'none'}`;
      rejectReady(new Error(`Input watcher exited before it was ready: ${details}`));
      return;
    }

    stopBot(`input watcher exited unexpectedly with code ${code ?? 'unknown'}`);
  });

  return readyPromise;
}

async function main() {
  await startUserInputWatcher();

  process.stdout.write('Bot started. Press a physical keyboard key or mouse button/wheel to stop it.\n');
  intervalId = setInterval(performAutomationStep, 1000);
}

main().catch((error) => {
  if (inputWatcher && !inputWatcher.killed) {
    inputWatcher.kill();
  }

  process.stderr.write(`Could not start bot: ${error.message}\n`);
  process.exit(1);
});
