# GitHub portfolio content

Reusable GitHub text for presenting **CloudBase Lab** and my GitHub profile.
This file is reference material — copy the relevant pieces into GitHub (profile
README, repo *About* field, pinned-repo description, repo topics). Nothing here
is wired into the stack.

> Honest framing: CloudBase Lab is a **learning and portfolio project**. The
> wording below is written for a beginner-to-junior DevOps profile — confident
> and practical, without overstating experience.

---

## A. GitHub profile README text

> Paste into a `README.md` in a repo named after your GitHub username
> (`Carrasco515/Carrasco515`) to show it on your profile.

```markdown
### Hi, I'm David 👋

I'm building my path into **DevOps and Platform Engineering**. I come at it from
the operations side: I like making systems run reliably, understanding how the
pieces fit together, and writing down how to operate them.

I'm currently focused on:

- 🐧 **Linux** as my daily environment
- 🐳 **Docker & Docker Compose** for containerised services
- ☸️ **Kubernetes** — learning it next
- 🔁 **CI** with GitHub Actions
- 📊 **Monitoring** and infrastructure **operations**

🚀 My main portfolio project is **[CloudBase Lab](https://github.com/Carrasco515/cloudbase-lab)** —
a self-hosted homelab where I run a multi-service stack end to end: reverse proxy
with HTTPS, monitoring, automated backups with tested restores, a safe update
strategy and CI.

My GitHub is where I document **practical, hands-on learning projects** as I grow
into the field. Feedback is always welcome.
```

---

## B. GitHub repository *About* description

**Short description (for the GitHub *About* field, ≤160 characters):**

```
Self-hosted DevOps homelab: Docker Compose stack with Traefik, Nextcloud, monitoring, automated backups, tested restores and GitHub Actions CI.
```

**Longer *About* text (3–5 sentences):**

> CloudBase Lab is a self-hosted homelab where I run a complete, multi-service
> private-cloud stack on a single machine with Docker Compose. A Nextcloud cloud
> sits behind a Traefik reverse proxy with local HTTPS, backed by MariaDB and
> Redis, monitored with Uptime Kuma, managed through Portainer and secured with a
> Vaultwarden password manager. Data is protected by automated backups with a
> read-only verification step and an isolated restore drill, images stay current
> through opt-in Watchtower updates, and a GitHub Actions pipeline validates the
> setup on every push. Everything runs locally by default — nothing is exposed to
> the internet — and the whole project is documented as code. It's my main DevOps
> learning and portfolio project.

---

## C. GitHub pinned repository text

> Short blurb for when CloudBase Lab is presented as a pinned repository.

**CloudBase Lab** — my main DevOps portfolio project. A self-hosted homelab that
runs a full Docker Compose stack (Traefik + HTTPS, Nextcloud, MariaDB, Redis,
monitoring, Portainer, Vaultwarden) with automated backups, tested restores, a
safe update strategy and GitHub Actions CI. Local-only by default, documented as
code.

**One-liner alternative:**

> Self-hosted Docker Compose homelab — reverse proxy, monitoring, automated
> backups with tested restores and CI. My main DevOps learning project.

---

## D. GitHub README intro

The README intro has been updated directly in `README.md`. It now states up
front that CloudBase Lab is a DevOps **learning and portfolio project**, what it
is, why I built it, what it demonstrates, and that everything runs locally by
default. See the top of [`README.md`](../README.md).

---

## E. Suggested GitHub repository topics

Add these in the repository's *About* → *Topics* (settings are changed in the
GitHub UI — this is only a suggestion list):

```
docker
docker-compose
devops
homelab
traefik
nextcloud
monitoring
backup
github-actions
platform-engineering
self-hosted
ci
```
