# How to run

## 1. Backend (terminal 1)

Open Docker Desktop first. This starts Postgres, updates the database
(needed once after pulling changes), then starts the server:

```sh
cd backend
source .venv/bin/activate
docker compose up -d
export DYLD_LIBRARY_PATH=/opt/homebrew/lib
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

FOR KELVIN, instead of the DYLD_LIBRARY_PATH line:

```sh
export DYLD_FALLBACK_LIBRARY_PATH="$(brew --prefix vips)/lib:$DYLD_FALLBACK_LIBRARY_PATH"
```

## 2. App (terminal 2)

On the Mac itself:

```sh
cd frontend
flutter run -d macos
```

The app opens on the login page: register or sign in. Everyone sees the
Guides tab (the last disk, after Settings) and can read published
guidelines; contributors can also write them (step 3).

On an iPhone simulator, start one first, then run on it:

```sh
open -a Simulator
flutter devices
flutter run -d "iPhone"
```

On a real phone: plug it in (or same Wi-Fi), unlock it, and use the start
of its name from `flutter devices`, e.g. `flutter run -d Kelvin`.

The app finds the server by itself over Bonjour (mDNS); no IP to set.

## See the database

Postgres runs in Docker. Open a SQL prompt in it:

```sh
cd backend
docker compose exec postgres psql -U app -d music_catalog
```

Useful commands inside it (`\q` to quit):

```sql
\dt
SELECT id, email, is_staff, date_joined FROM auth_user;
SELECT id, title, status, version FROM guidelines_guideline;
SELECT guideline_id, metric, operator, value, unit FROM guidelines_rubric;
SELECT id, title, composer, composed_date FROM scores_score LIMIT 20;
```

Or connect a GUI (TablePlus, DBeaver, Postico): host `localhost`, port
`5432`, database `music_catalog`, user `app`, password from
`backend/.env` (`POSTGRES_PASSWORD`).

## 3. Writing guidelines (contributors only)

Register in the app, then make that account a contributor:

```sh
cd backend
source .venv/bin/activate
python manage.py guideline_contributor add you@example.com
```

In the app: Settings → Log out, then sign in again. The Guides tab now has
a "New guideline" button and Mine / All.

## Test the core feature

```sh
afplay ~/Desktop/fur_elise_mistakes.wav
```
