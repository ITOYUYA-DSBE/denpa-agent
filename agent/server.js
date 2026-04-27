const express = require("express");
const cors = require("cors");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = 8787;

app.use(cors());
app.use(express.json());

const reposPath = path.join(__dirname, "repos.json");
const repos = JSON.parse(fs.readFileSync(reposPath, "utf-8"));

const jobs = new Map();

function createJob(repo, prompt, engine, accessLevel) {
  const id = `job_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  const job = {
    id,
    repo,
    prompt,
    engine,
    accessLevel,
    status: "queued",
    stdout: "",
    stderr: "",
    startedAt: null,
    finishedAt: null,
    exitCode: null,
  };

  jobs.set(id, job);
  return job;
}

function getCodexArgs(prompt, accessLevel) {
  switch (accessLevel) {
    case "listen":
      // 読む・説明するだけを想定。
      // Codex側の権限挙動はCLIの設定にも依存する。
      return ["exec", prompt];

    case "touch":
      // ファイル編集まで許可する想定。
      return ["exec", "--full-auto", prompt];

    case "possess":
      // 現状は touch と同じ。
      // 将来ここにより強い実行権限や別設定を入れる。
      return ["exec", "--full-auto", prompt];

    default:
      return ["exec", prompt];
  }
}

function getClaudeArgs(prompt, accessLevel) {
  switch (accessLevel) {
    case "listen":
      // 非対話モード。基本は返答のみ。
      return ["-p", "--output-format", "text", prompt];

    case "touch":
      // ファイル編集系ツールを許可。
      return [
        "-p",
        "--output-format",
        "text",
        "--allowedTools",
        "Read,Edit,MultiEdit,Write",
        prompt,
      ];

    case "possess":
      // 強い権限。信頼できるローカル環境のみで使う。
      return [
        "-p",
        "--output-format",
        "text",
        "--dangerously-skip-permissions",
        prompt,
      ];

    default:
      return ["-p", "--output-format", "text", prompt];
  }
}

app.get("/", (req, res) => {
  res.json({
    ok: true,
    message: "Denpa Agent is running",
    subtitle: "A spatial receiver for local AI agents.",
    endpoints: {
      health: "GET /health",
      repos: "GET /repos",
      run: "POST /run",
      build: "POST /build",
      status: "GET /status/:jobId",
      jobs: "GET /jobs",
    },
  });
});

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

app.get("/repos", (req, res) => {
  res.json({ repos: Object.keys(repos) });
});

app.get("/jobs", (req, res) => {
  res.json({
    jobs: Array.from(jobs.values()).map((job) => ({
      id: job.id,
      repo: job.repo,
      engine: job.engine,
      accessLevel: job.accessLevel,
      status: job.status,
      startedAt: job.startedAt,
      finishedAt: job.finishedAt,
      exitCode: job.exitCode,
    })),
  });
});

app.get("/status/:jobId", (req, res) => {
  const job = jobs.get(req.params.jobId);

  if (!job) {
    return res.status(404).json({ error: "Job not found" });
  }

  res.json(job);
});

app.post("/run", (req, res) => {
  const {
    repo,
    prompt,
    engine = "codex",
    accessLevel = "listen",
  } = req.body;

  if (!repo || !prompt) {
    return res.status(400).json({
      error: "repo and prompt are required",
    });
  }

  const repoPath = repos[repo];

  if (!repoPath) {
    return res.status(400).json({
      error: `Unknown repo: ${repo}`,
      availableRepos: Object.keys(repos),
    });
  }

  if (!fs.existsSync(repoPath)) {
    return res.status(400).json({
      error: `Repo path does not exist: ${repoPath}`,
    });
  }

  const normalizedEngine = engine === "claude" ? "claude" : "codex";

  const normalizedAccessLevel = ["listen", "touch", "possess"].includes(accessLevel)
    ? accessLevel
    : "listen";

  const job = createJob(
    repo,
    prompt,
    normalizedEngine,
    normalizedAccessLevel
  );

  job.status = "running";
  job.startedAt = new Date().toISOString();

  console.log("========== DENPA TRANSMISSION ==========");
  console.log("repo:", repo);
  console.log("engine:", normalizedEngine);
  console.log("accessLevel:", normalizedAccessLevel);
  console.log("prompt:", prompt);

  let command;
  let args;

  if (normalizedEngine === "claude") {
    command = "claude";
    args = getClaudeArgs(prompt, normalizedAccessLevel);
  } else {
    command = "codex";
    args = getCodexArgs(prompt, normalizedAccessLevel);
  }

  console.log("command:", command);
  console.log("args:", args);

  const child = spawn(command, args, {
    cwd: repoPath,
    env: process.env,
    shell: false,
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout.on("data", (data) => {
    const text = data.toString();
    console.log("[stdout]", text);
    job.stdout += text;
  });

  child.stderr.on("data", (data) => {
    const text = data.toString();
    console.log("[stderr]", text);
    job.stderr += text;
  });

  child.on("error", (err) => {
    job.status = "failed";
    job.stderr += `\n[spawn error] ${err.message}\n`;
    job.finishedAt = new Date().toISOString();
    job.exitCode = -1;
    console.log("[spawn error]", err.message);
  });

  child.on("close", (code) => {
    job.exitCode = code;
    job.finishedAt = new Date().toISOString();
    job.status = code === 0 ? "completed" : "failed";
    console.log("child closed with code:", code);
  });

  res.json({
    ok: true,
    jobId: job.id,
    status: job.status,
    engine: normalizedEngine,
    accessLevel: normalizedAccessLevel,
  });
});

// 既存のBuildボタン用。UIから消しても残しておいてOK。
app.post("/build", (req, res) => {
  const { repo } = req.body;

  if (!repo) {
    return res.status(400).json({
      error: "repo is required",
    });
  }

  const repoPath = repos[repo];

  if (!repoPath) {
    return res.status(400).json({
      error: `Unknown repo: ${repo}`,
      availableRepos: Object.keys(repos),
    });
  }

  if (!fs.existsSync(repoPath)) {
    return res.status(400).json({
      error: `Repo path does not exist: ${repoPath}`,
    });
  }

  const job = createJob(repo, "__BUILD__", "xcodebuild", "possess");
  job.status = "running";
  job.startedAt = new Date().toISOString();

  const child = spawn(
    "xcodebuild",
    [
      "-project",
      "sampling.xcodeproj",
      "-scheme",
      "sampling",
      "build",
    ],
    {
      cwd: repoPath,
      env: process.env,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
    }
  );

  child.stdout.on("data", (data) => {
    job.stdout += data.toString();
  });

  child.stderr.on("data", (data) => {
    job.stderr += data.toString();
  });

  child.on("error", (err) => {
    job.status = "failed";
    job.stderr += `\n[spawn error] ${err.message}\n`;
    job.finishedAt = new Date().toISOString();
    job.exitCode = -1;
  });

  child.on("close", (code) => {
    job.exitCode = code;
    job.finishedAt = new Date().toISOString();
    job.status = code === 0 ? "completed" : "failed";
  });

  res.json({
    ok: true,
    jobId: job.id,
    status: job.status,
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Denpa Agent listening on http://0.0.0.0:${PORT}`);
});