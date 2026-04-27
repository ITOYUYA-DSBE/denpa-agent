# Denpa Agent 📡

**A spatial receiver for local AI agents.**

Denpa Agent は、Apple Vision Pro から Mac 上で動くローカルAIコーディングエージェントを操作するための実験的な visionOS アプリです。

Codex / Claude Code を切り替え、Access Level を選び、空間UIから Prompt を送って Transmission として結果を受け取ります。

> Experimental prototype. App Store向けの正式製品ではありません。

## Core UI

- **Channel**: Codex / Claude Code を切り替える
- **Access Level**: AIにどこまで権限を渡すか選ぶ
- **Prompt**: 指示する
- **Transmission**: 結果を受け取る

## Access Levels

- **Listen**: 説明や回答を受け取るモード
- **Touch**: ファイル編集を許可するモード
- **Possess**: ファイル編集やコマンド実行など、より強い操作を許可するモード

> Possess mode can be dangerous. Use only in trusted local repositories.

## Architecture

Apple Vision Pro  
→ Tailscale / local network  
→ Mac  
→ Denpa Agent Server  
→ Codex / Claude Code

## Requirements

### Mac

- Node.js
- npm
- Codex CLI または Claude Code CLI
- 外部ネットワークから接続する場合は Tailscale

### Apple Vision Pro

- visionOS
- Xcode

## Setup

### 1. Start the local agent server

```bash
cd agent
npm install
cp repos.example.json repos.json
node server.js