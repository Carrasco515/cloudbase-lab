# CloudBase Lab — Screenshots

Screenshots make the project tangible for readers who will not run the stack
themselves. They live in `docs/images/` and are embedded below.

> **Status:** work in progress — placeholders below are filled in as the
> screenshots are captured.

## Capture checklist

Before committing any screenshot:

- [ ] No real passwords, tokens, session URLs or personal e-mail addresses visible
- [ ] No real file names / calendar entries in Nextcloud views
- [ ] Vaultwarden: never screenshot vault contents — the login page is enough
- [ ] Prefer the `https://*.cloudbase.local` URLs in the address bar (shows the
      Traefik + HTTPS path)

## Planned screenshots

| File | What it shows |
|---|---|
| `images/homepage.png` | Homepage dashboard with links to all services |
| `images/traefik-dashboard.png` | Traefik dashboard — routers for every `*.cloudbase.local` hostname |
| `images/uptime-kuma.png` | Uptime Kuma with the HTTP/TCP monitors green |
| `images/nextcloud.png` | Nextcloud over `https://nextcloud.cloudbase.local` |
| `images/portainer.png` | Portainer showing the `cloudbase-*` containers healthy |
| `images/restore-drill.png` | Terminal output of a successful `restore-drill.sh` run |

<!-- Embed as they are added:
![Homepage dashboard](images/homepage.png)
![Traefik dashboard](images/traefik-dashboard.png)
![Uptime Kuma monitors](images/uptime-kuma.png)
![Nextcloud over HTTPS](images/nextcloud.png)
![Portainer](images/portainer.png)
![Restore drill](images/restore-drill.png)
-->
