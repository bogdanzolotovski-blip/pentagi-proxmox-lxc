# PentAGI 2.1.0 для Proxmox LXC

Этот пакет создаёт отдельный **непривилегированный Ubuntu 24.04 LXC** и устанавливает в него Docker Engine, Compose и [PentAGI](https://github.com/vxcontrol/pentagi) из версии `v2.1.0` (коммит `a112db206b2fb7866c367c33348f52f5cdc207d0`). Образы закреплены в `payload/images.lock` по digest и проверяются по image ID до запуска.

PentAGI запускает дополнительные Docker-контейнеры для инструментов. Для них LXC требует `nesting=1,keyctl=1`. Proxmox [рекомендует VM для Docker](https://pve.proxmox.com/pve-docs-9-beta/pct.1.html); здесь используется запрошенный LXC, и итоговую работоспособность вложенного Docker нужно проверить на конкретном узле. Не разворачивайте контейнер в сети с доступом к чужим целям без правил доступа.

## Требования

- Proxmox VE с доступом root к `pct` и `pveam`, хранилищем для Ubuntu 24.04 template, свободным CTID, мостом и IP/DHCP.
- Архитектура amd64, минимум 2 vCPU, 4 ГБ RAM и 20 ГБ свободного места по документации PentAGI. В примере выделены 4 vCPU, 8 ГБ RAM и 64 ГБ диска с учётом Kali и базы.
- Доступ к Ubuntu и Docker APT-репозиториям и к реестрам Docker Hub/Quay, если `images.tar` не передан отдельно.
- Публичный SSH-ключ администратора. Секреты LLM задаются только после установки в `/opt/pentagi/.env` внутри CT.

## Установка

Передайте этот каталог на узел Proxmox. На нём выполните:

```bash
cp config.env.example config.env
nano config.env
chmod +x deploy.sh install-existing.sh verify.sh payload/*.sh
sudo ./deploy.sh ./config.env
sudo ./verify.sh CTID
```

Скрипт откажется изменять существующий CTID. Он скачает Ubuntu template при необходимости и в контейнере установит Docker Engine/Compose из [официального Docker APT-репозитория](https://docs.docker.com/engine/install/ubuntu/). До запуска PentAGI он скачает все шесть закреплённых образов и проверит их image ID. Kali-образ проверяется запуском без сети и наличием `nmap`, `sqlmap`, `nikto`, `nuclei`, `ffuf`, `hydra`, `msfconsole`, `gobuster`, `feroxbuster`, `amass`.

Если подходящий непривилегированный Ubuntu 24.04 CT уже существует и у него включены `nesting=1,keyctl=1`, установите в него без создания нового:

```bash
sudo ./install-existing.sh CTID /path/to/id_ed25519.pub
sudo ./verify.sh CTID
```

Локальный архив Docker-образов `pentagi-proxmox-images-v2.1.0-amd64.tar.zst` занимает 7 322 951 369 байт; SHA-256: `e8239e228d7ac769f0fd0d4e0dd558ad71c9081fac9a19b27bdd5408a71b994c`. Скопируйте его на узел Proxmox как `images.tar.zst` рядом с `deploy.sh` **до** запуска. Скрипт проверит SHA-256 на узле и после передачи в CT, распакует через `zstd | docker load` и скачает из реестров только недостающие образы. Сам архив в Git не включён.

Если архив скачан по частям из [GitHub Releases](https://github.com/bogdanzolotovski-blip/pentagi-proxmox-lxc/releases/tag/v2.1.0-lxc.1), положите все пять частей в корень репозитория и запустите `./assemble-images.sh`. Скрипт проверит SHA-256 каждой части и собранного архива.

Для доступа к UI узнайте адрес CT через `pct exec CTID -- hostname -I` и откройте SSH-туннель с вашего компьютера:

```bash
ssh -L 8443:127.0.0.1:8443 pentagi-admin@CT_IP
```

Затем откройте `https://localhost:8443`. Стандартные учётные данные PentAGI указаны в [официальном руководстве](https://pentagi.com/get-started); смените пароль при первом входе. Порт UI в CT слушает только `127.0.0.1`.

## LLM и проверка работы

Без настроенного LLM-провайдера PentAGI не сможет запускать задачи. Внесите ключ и нужные переменные провайдера в `/opt/pentagi/.env` внутри CT, затем выполните:

```bash
cd /opt/pentagi
docker compose up -d --pull never
docker exec pentagi /opt/pentagi/bin/ctester -verbose
docker exec pentagi /opt/pentagi/bin/etester test -verbose
```

Проверка контейнеров и журналов с Proxmox:

```bash
sudo ./verify.sh CTID
pct exec CTID -- docker compose -f /opt/pentagi/docker-compose.yml logs --tail=100 pentagi
```

Исходники PentAGI и его [EULA](upstream/EULA.md) включены в каталог `upstream` только в виде файлов, нужных для развёртывания. Не добавляйте `config.env`, `.env`, токены или данные Docker в Git. Используйте PentAGI только на ресурсах, тестирование которых разрешено.
