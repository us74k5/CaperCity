#!/usr/bin/env bash
# Build Caper City and push it to the server.
#   deploy/deploy.sh root@198.46.218.186          # build + upload + restart
#   deploy/deploy.sh root@198.46.218.186 --setup  # first time: also install nginx, the service and firewall rules
# Set DOMAIN=game.example.com on --setup to get the certificate for a domain instead of the server's IP.
# Needs the Godot 4.7.2 editor (Flatpak or GODOT=/path/to/godot) with the Web and Linux export templates.
set -euo pipefail
HOST=${1:?usage: deploy/deploy.sh user@host [--setup]}
SETUP=${2:-}
cd "$(dirname "$0")/.."
GODOT=${GODOT:-"flatpak run org.godotengine.Godot"}

echo "== exporting"
mkdir -p export/web export/server
touch export/.gdignore
$GODOT --headless --path . --export-release "Web" export/web/index.html
$GODOT --headless --path . --export-release "Linux Server" export/server/capercity.x86_64
rm -f export/web/*.import
for f in export/web/index.wasm export/web/index.pck export/web/index.js; do gzip -9 -k -f "$f"; done

if [ "$SETUP" = "--setup" ]; then
	echo "== first-time setup on $HOST"
	scp deploy/nginx.conf "$HOST":/tmp/capercity-nginx.conf
	scp deploy/capercity.service "$HOST":/tmp/capercity.service
	ssh "$HOST" "echo ${DOMAIN:-${HOST#*@}} > /tmp/capercity-name"
	ssh "$HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
if command -v apt-get >/dev/null; then
	DEBIAN_FRONTEND=noninteractive apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -yq nginx rsync
elif command -v dnf >/dev/null; then
	dnf install -y nginx rsync
fi
id capercity >/dev/null 2>&1 || useradd --system --home /var/lib/capercity --shell /usr/sbin/nologin capercity
mkdir -p /opt/capercity /var/www/capercity /var/www/acme /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/capercity.crt ]; then
	# a stand-in so nginx starts; Let's Encrypt's certificate replaces it below
	openssl req -x509 -nodes -newkey rsa:2048 -days 2 -subj "/CN=capercity" \
		-keyout /etc/nginx/ssl/capercity.key -out /etc/nginx/ssl/capercity.crt 2>/dev/null
fi
install -m 644 /tmp/capercity-nginx.conf /etc/nginx/conf.d/capercity.conf
rm -f /etc/nginx/sites-enabled/default   # the distro's placeholder page also claims port 80
install -m 644 /tmp/capercity.service /etc/systemd/system/capercity.service
systemctl daemon-reload
systemctl enable nginx capercity
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 7777/tcp; fi
if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
	firewall-cmd --permanent --add-service=http; firewall-cmd --permanent --add-service=https
	firewall-cmd --permanent --add-port=7777/tcp; firewall-cmd --reload
fi
if command -v setsebool >/dev/null; then setsebool -P httpd_can_network_connect 1 || true; fi
nginx -t && systemctl reload-or-restart nginx

# HTTPS: Let's Encrypt via acme.sh. A bare IP gets a short-lived (6-day) certificate, renewed by acme.sh's daily cron.
NAME=$(cat /tmp/capercity-name)
command -v git >/dev/null || { apt-get install -yq git 2>/dev/null || dnf install -y git; }
if [ ! -d /root/.acme.sh ]; then
	git clone -q --depth 1 https://github.com/acmesh-official/acme.sh.git /tmp/acme
	(cd /tmp/acme && ./acme.sh --install >/dev/null)
	rm -rf /tmp/acme
fi
/root/.acme.sh/acme.sh --install-cronjob >/dev/null
PROFILE=""
if [[ "$NAME" =~ ^[0-9.]+$ ]]; then PROFILE="--cert-profile shortlived --days 3"; fi
/root/.acme.sh/acme.sh --issue --server letsencrypt -d "$NAME" --webroot /var/www/acme $PROFILE || [ $? -eq 2 ]   # 2 = still valid
/root/.acme.sh/acme.sh --install-cert -d "$NAME" --ecc --key-file /etc/nginx/ssl/capercity.key \
	--fullchain-file /etc/nginx/ssl/capercity.crt --reloadcmd "systemctl reload nginx"
REMOTE
fi

echo "== uploading"
rsync -az --delete export/web/ "$HOST":/var/www/capercity/
rsync -az export/server/capercity.x86_64 "$HOST":/opt/capercity/capercity.x86_64.new
ssh "$HOST" 'set -e
	mv /opt/capercity/capercity.x86_64.new /opt/capercity/capercity.x86_64
	chmod 755 /opt/capercity/capercity.x86_64
	chmod -R a+rX /var/www/capercity
	if command -v restorecon >/dev/null; then restorecon -R /var/www/capercity /opt/capercity || true; fi
	nginx -t && systemctl reload-or-restart nginx
	systemctl restart capercity
	sleep 1; systemctl --no-pager --lines=3 status capercity'
echo "== done: https://${DOMAIN:-${HOST#*@}}/"
