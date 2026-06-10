FROM python:3.12-slim

# Install yt-dlp + ffmpeg
RUN apt-get update && apt-get install -y ffmpeg curl \
 && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
         -o /usr/local/bin/yt-dlp \
 && chmod +x /usr/local/bin/yt-dlp \
 && pip install flask \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY main.py .

EXPOSE 8080
CMD ["python", "main.py"]