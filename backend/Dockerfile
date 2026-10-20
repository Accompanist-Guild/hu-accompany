# The backend as one container for Google Cloud Run. Build from backend/:
#   docker build --platform linux/amd64 -t hu-accompany-backend .
# Run locally (production mode refuses to start without these three):
#   docker run --rm -p 8080:8080 -e DJANGO_SECRET_KEY=x -e ALLOWED_HOSTS=localhost -e APP_API_KEY=k hu-accompany-backend
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# fluidsynth turns MIDI into sound and fluid-soundfont-gm provides the General MIDI soundfont it needs
# (/usr/share/sounds/sf2/FluidR3_GM.sf2, one of the places hum/engine/accompanist/audio/render.py looks).
# libgomp1 is the OpenMP runtime that onnxruntime wants on a slim image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends fluidsynth fluid-soundfont-gm libsndfile1 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies first, so editing code doesn't reinstall them. basic-pitch goes in with --no-deps:
# its normal install pulls in TensorFlow, which the app doesn't use (see requirements-prod.txt).
COPY requirements-prod.txt .
RUN pip install -r requirements-prod.txt && pip install --no-deps basic-pitch

COPY . .

# Production mode is on in this image, so a container started without its secrets fails loudly
# instead of running open. The hum feature keeps its working files under HUM_DATA_DIR, which on
# Cloud Run is memory-backed, so deploy/gunicorn.conf.py also sweeps old ones out.
ENV DJANGO_ENV=production \
    HUM_DATA_DIR=/tmp/hum_data \
    RUNS_DIR=/tmp/hum_data/runs \
    PORT=8080 \
    NUMBA_CACHE_DIR=/tmp/numba_cache

# A real home folder: librosa (numba) and music21 write caches and settings there or to /tmp, and fail
# at the first hum request if the user has nowhere to write.
RUN useradd --system --create-home app
USER app

EXPOSE 8080
CMD ["gunicorn", "-c", "deploy/gunicorn.conf.py", "server.wsgi:application"]
