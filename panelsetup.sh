#!/bin/bash
echo "[INFO] Starting Firebase VPS Keepalive..."

# 1. Keepalive loop (touch a file every minute)
while true; do
  date >> keepalive.log
  touch keepalive.txt
  sleep 60
done &
echo "[INFO] Keepalive loop started."

# 2. Start ngrok (with proper logging)
./ngrok tcp 22 --log=ngrok.log > /dev/null 2>&1 &
echo "[INFO] Ngrok tunnel started."

# 3. Show tunnel URL every 30s
while true; do
  curl -s http://127.0.0.1:4040/api/tunnels | grep -o "tcp://[0-9a-zA-Z.:]*"
  sleep 30
done &
echo "[INFO] URL watcher started."

wait
