# Claude Code Plugins by Franz

Marketplace for my Claude Code plugins.

## Installation

In Claude Code, run:

```
/plugin marketplace add mulkatz/claude-plugins
```

Then install any plugin:

```
/plugin install anvil@mulkatz
/plugin install spark@mulkatz
```

Auto-updates: `/plugin marketplace update mulkatz`

## Plugins

| Plugin | Description | Repo |
| ------ | ----------- | ---- |
| [Anvil](https://github.com/mulkatz/anvil) | Adversarial thinking through structured debates | [mulkatz/anvil](https://github.com/mulkatz/anvil) |
| [Spark](https://github.com/mulkatz/spark) | Collaborative ideation through multi-persona brainstorming | [mulkatz/spark](https://github.com/mulkatz/spark) |

## Maintenance

Plugin files are synced from their source repos. After updating a plugin:

```bash
./sync.sh          # sync all plugins
./sync.sh spark    # sync one plugin
git add -A && git commit -m "sync: update plugins" && git push
```
