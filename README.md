<h1 align="center">mulkatz plugins</h1>

<p align="center">
  <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> plugin marketplace by <a href="https://github.com/mulkatz">Franz Benthin</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-marketplace-blueviolet?style=flat-square" alt="Claude Code Marketplace">
  <img src="https://img.shields.io/badge/plugins-2-blue?style=flat-square" alt="2 plugins">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License"></a>
</p>

## Quick Start

```
/plugin marketplace add mulkatz/claude-plugins
```

Then install what you need:

```
/plugin install anvil@mulkatz
/plugin install spark@mulkatz
```

---

## Plugins

<table>
<tr>
<td width="80" align="center">
<a href="https://github.com/mulkatz/anvil"><img src="https://raw.githubusercontent.com/mulkatz/anvil/main/assets/icon.png" width="48" alt="Anvil"></a>
</td>
<td>
<h3><a href="https://github.com/mulkatz/anvil">Anvil</a></h3>
<strong>Adversarial thinking through structured debates.</strong><br>
Stress-test ideas by rotating through Advocate, Critic, and Synthesizer phases. Supports multiple debate modes (analyst, philosopher, devil's advocate, stakeholders), decision frameworks (ADR, pre-mortem, red-team), code-aware context, web research, custom personas, and interactive steering.
<br><br>
<code>/anvil:anvil "Should we migrate to microservices?"</code>
</td>
</tr>
<tr>
<td width="80" align="center">
<a href="https://github.com/mulkatz/spark"><img src="https://raw.githubusercontent.com/mulkatz/spark/main/assets/icon.png" width="48" alt="Spark"></a>
</td>
<td>
<h3><a href="https://github.com/mulkatz/spark">Spark</a></h3>
<strong>Collaborative ideation through multi-persona brainstorming.</strong><br>
Generate surprising ideas by rotating 3 AI personas through Seed, Cross-Pollinate, and Synthesize phases. Each persona brings a distinct worldview, vocabulary, and blind spots. Research-backed design with anti-convergence mechanisms.
<br><br>
<code>/spark "How can we reduce onboarding time for new developers?"</code>
</td>
</tr>
</table>

---

## Managing Plugins

```bash
# Update marketplace to get latest plugin versions
/plugin marketplace update mulkatz

# Remove a plugin
/plugin uninstall anvil@mulkatz

# Remove marketplace entirely
/plugin marketplace remove mulkatz
```
