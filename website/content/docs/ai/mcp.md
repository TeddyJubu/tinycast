---
title: Connections
description: Tag an app or a remote MCP server so AI Chat can call its tools.
---

Connections give a model tools from an app, such as mail or an issue tracker, or from a remote
[Model Context Protocol](https://modelcontextprotocol.io) server. Tinycast reaches them through
[Composio](https://composio.dev). When you tag one, AI Chat offers its tools during your conversations.

Turn it on in **Settings → AI → Connections → Enable connections**. It's **off** by default, and it
only applies while [AI Chat](/docs/ai) is on. While either one is off, Tinycast doesn't contact
Composio or any tagged server.

## Composio API key

Paste a project API key from [composio.dev](https://composio.dev) and click **Save**. The key is
stored in your login Keychain, never in preferences, logs or backups. **Remove** deletes it. Without
a key, the catalog and sign-in can't run.

## Tagging an app

**Add connection** opens the catalog.

- Search for an app. Each card shows its name and a short description.
- **Connect** opens Composio's sign-in page in your browser. When the account is connected, the card
  says **Connected**. An app that needs no sign-in says **No sign-in**.
- **Tag** includes the app in chat. The button then shows its handle, like `@gmail`. Click that
  handle to remove the tag. Chat stops offering it, and its stored credential is deleted.

The same list in Settings shows each tagged app, its handle, and whether chat can reach it. The link
button opens sign-in again. Removing a row does the same as removing the tag.

## Adding a remote MCP server

In the same window, choose **MCP server**. Enter a name and a public HTTPS address, pick **No
sign-in**, **API key** or **OAuth**, then **Add and tag**. Composio registers the server and Tinycast
tags it like an app. If it needs a sign-in, the browser opens Composio's page.

The address has to be reachable from the internet. Plain HTTP, and an address on this Mac such as
`localhost`, are refused: Composio calls the server, not Tinycast.

A command that runs on your Mac is not added here. A server you saved before Connections still
appears in the list, and you can remove it. It is not edited here.

## Using tools in a chat

The model is offered the tools from every tagged connection. When it calls one, a row appears in the
reply with a spinner while the tool runs. Consecutive calls share one line, which shows the current
call while it runs, then the number of calls and any failures. Click the line to see each call. The
reply continues after it, and the calls are saved with the chat.

### Talking to one connection

Start a message with a handle, like `@gmail find the latest invoice`. A tools icon after your text
shows that the handle was recognized. Only that connection's tools are offered, and the handle is
removed before the message is sent. A handle that doesn't match any connection is sent as you typed
it.

### Permission to run

The first tool call in a conversation asks:

- **Always Allow** remembers your choice for that connection.
- **Allow This Chat** allows calls for this conversation only.
- **Don't Allow** refuses this one call. <kbd>esc</kbd> does the same, and the next call asks again.

A refused or failed call isn't treated as an error. The model is told what happened and can answer
without the tool.

## Which models get tools

Tools are offered to **API connections** (OpenAI API, Anthropic Claude, Google Gemini, OpenRouter and
OpenAI Compatible endpoints) and to the installed **Codex** and **Claude** commands. With those two
commands, the command-line tool calls the tools itself. The connections, the confirmation and the
rows in the reply work the same as everywhere else. Tinycast never changes either command's settings.

Your own Codex and Claude MCP servers aren't used in a Tinycast chat. Claude is told to use only
Tinycast's list. Codex receives Tinycast's connections under their own names, like `tinycast-gmail`,
and every server in your Codex configuration is turned off for that chat, so one of your servers
named `gmail` is never confused with Tinycast's `@gmail`. If Tinycast can't read which servers your
Codex configuration has, or one of them has a dot or `=` in its name, Tinycast won't start Codex at
all, and the Codex row in Settings explains why.

A few things work differently with Codex:

- Adding or removing a connection restarts its helper process, which adds about a second to your
  next message. The same happens when you switch between a message that starts with a handle, like
  `@gmail`, and one that doesn't, because each offers a different set of connections.
- Turning connections off, or removing one, stops the helper right away so nothing it started keeps
  running. If a reply is in progress at that moment, the helper keeps going until your next message
  or until it's been idle for ten minutes.
- Codex can also read content a server publishes, like Notion's guides, without asking. **Ask Each
  Chat** applies to a connection's tools but not to this content. Removing the connection keeps it
  out completely.

Apple Intelligence and the installed Grok, OpenCode and Cursor commands never get tools. With those,
chat works the same as it does without connections.

If your organization installs a Claude Code MCP policy, that policy decides MCP for the Claude
command, and Tinycast doesn't pass any connections to it. The Providers row tells you when this
applies.

## Limits

- **Settings → AI → Chat → Tool call rounds** sets how many rounds of tool calls a single reply can
  use: **25** by default, or 10, 50, 100 or **Unlimited**. A model that keeps calling tools without
  answering is stuck, so when it reaches the limit, the reply ends with a note saying how many
  rounds it used. With Codex, the limit counts individual tool calls instead of rounds, which stops
  a runaway reply sooner. With Unlimited, a reply only ends when the model finishes, when you click
  **Stop**, or, on an API connection, when the tool history passes 1 MB. The reply keeps running
  while the palette is hidden, and every round is billed by your provider or counted against your
  plan.
- Each tool result, and the total of all results in one reply, has a size limit.
- Connections are contacted when you use chat. A server you saved earlier that runs on your Mac
  stops after **10 minutes** without use, or when Tinycast quits. While Codex or Claude is the chat
  model, that local server is started by that command instead of by Tinycast, so it never runs
  twice. Its row in Settings shows **Stopped** until you switch to an API model.
- Tinycast doesn't offer anything back to servers. Requests from a server, like sampling, are
  declined.

## Backups

Neither the switch, your Composio key, nor the list of tagged connections is included in a
[backup](/docs/reference/backup). You add them on each Mac.
