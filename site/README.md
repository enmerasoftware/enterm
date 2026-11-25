# enterm.enmeraapps.com

The website and the Library's community shelf, served by one small Node server with no dependencies.

| Path | What |
|---|---|
| `public/` | The static site: landing page, `/library` (reviewed and community items), `/privacy`, 404 |
| `server.mjs` | Serves `public/` and the API below; data in one JSON file (`$STATE_DIRECTORY`, `DATA_DIR`) |
| `admin.html` | `/admin`: review, hide or delete community items; copy one as a `library/prompts/` file |
| `rules.mjs`, `TAGS.md` | Links to `library/scripts/rules.mjs` and `library/TAGS.md`: the same checks and tags as the reviewed shelf |
| `install.sh` | On the server, as root: installs to `/opt/enterm-web`, the `enterm-web` systemd unit and the nginx directives |
| `deploy.sh` | From a Mac: runs the tests, copies everything over SSH and runs `install.sh` |

## API

| Request | Answer |
|---|---|
| `GET /api/library/community?sort=top\|new` | `{items}`: visible community items |
| `GET /api/library/votes` | `{votes: {id: count}}` for every liked item, reviewed ones too |
| `POST /api/library/submit` | `{kind, title, summary, text, test?, programs, tags, author, lang, device}` → `201 {item}`, `400 {error, field}`, `409`, `429` |
| `POST /api/library/vote` | `{id, device, like?}` → `{id, liked, votes}` |
| `POST /api/library/report` | `{id, device, reason}`; three Macs hide an unreviewed item |
| `POST /api/library/delete` | `{id, device}`: only the Mac that shared it |
| `GET /api/admin/items`, `POST /api/admin/items/<id>` | With `Authorization: Bearer <admin-token>`; actions `hide`, `show`, `review`, `unreview`, `delete` |

`device` is the random id the app makes once per Mac. The server keeps only salted hashes of it and of the client address. Limits: five shares an hour and twenty a day per Mac and per address; 300 likes and 30 reports an hour per address.

## Run and test

```bash
node site/server.mjs            # http://127.0.0.1:8788, data in site/.data
node --test site/
```

The app reads `https://enterm.enmeraapps.com`; `ENTERM_LIBRARY_SERVER=http://localhost:8788` points a test copy at a local server.

## Deploy

nginx sends WebSocket upgrades to the relay (`relay/`, port 8787) and everything else here (port 8788); `install.sh` writes that into the domain's Plesk directives, backing up the old ones and rolling back if `nginx -t` fails. The admin token is created on first start in `/var/lib/enterm-web/admin-token`.

```bash
site/deploy.sh   # reads SITE_HOST and SITE_PORT from ~/.config/enterm/site.env
```
