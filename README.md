# sitios-deploy-vjtech
Sitios deploy en server vjtech.

Dos sitios estaticos servidos por un reverse proxy nginx en el **puerto 80**:

| Ruta | Servicio | Repo |
|---|---|---|
| `/thunder-team/` | `thunder` | sitio-team-thunder |
| `/vj-tech/` | `vjtech` | landing-page-vjtech |

## Setup one-time en el EC2

```bash
sudo systemctl enable --now docker
sudo apt install -y docker-compose-plugin   # si no esta
sudo ss -ltnp | grep ':80 '                 # debe estar libre
mkdir -p ~/sitios
git clone --branch master https://github.com/jricardo369/sitios-deploy-vjtech.git ~/sitios/sitios-deploy-vjtech
cd ~/sitios/sitios-deploy-vjtech
bash deploy.sh
```

Security Group: abrir inbound **TCP 80** desde `0.0.0.0/0`.

## Deploys

Automaticos por GitHub Actions (push a `master` en cualquiera de los dos
repos de sitios). Manual: `cd ~/sitios/sitios-deploy-vjtech && bash deploy.sh`.

Secrets requeridos en cada repo de sitio: `EC2_HOST`, `EC2_USER`,
`EC2_SSH_KEY`, `EC2_PATH` (= `sitios/sitios-deploy-vjtech` o ruta absoluta).
