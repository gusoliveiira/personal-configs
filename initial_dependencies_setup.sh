#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu/WSL bootstrap
# Instala: git, Erlang, Elixir, Cursor Desktop e Cursor CLI
#
# Uso:
#   ./bootstrap_wsl_dev_env.sh
#   ./bootstrap_wsl_dev_env.sh --skip-cursor-desktop
#   ./bootstrap_wsl_dev_env.sh --skip-cursor-cli
#   ./bootstrap_wsl_dev_env.sh --skip-git --skip-elixir

SKIP_GIT=false
SKIP_ELIXIR=false
SKIP_CURSOR_DESKTOP=false
SKIP_CURSOR_CLI=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  printf "\n${BLUE}[%s]${NC} %s\n" "$(date '+%H:%M:%S')" "$*"
}

warn() {
  printf "\n${YELLOW}[warn]${NC} %s\n" "$*"
}

success() {
  printf "\n${GREEN}[ok]${NC} %s\n" "$*"
}

die() {
  printf "\n${RED}[erro]${NC} %s\n" "$*"
  exit 1
}

on_error() {
  local exit_code=$?
  printf "\n${RED}[erro]${NC} falha na linha %s (exit code %s)\n" "$1" "$exit_code"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

usage() {
  cat <<'EOF'
Uso: ./bootstrap_wsl_dev_env.sh [opcoes]

Opcoes:
  --skip-git              Nao instala Git
  --skip-elixir           Nao instala Erlang/Elixir
  --skip-cursor-desktop   Nao instala Cursor Desktop
  --skip-cursor-cli       Nao instala Cursor CLI
  -h, --help              Exibe esta ajuda
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-git)
        SKIP_GIT=true
        ;;
      --skip-elixir)
        SKIP_ELIXIR=true
        ;;
      --skip-cursor-desktop)
        SKIP_CURSOR_DESKTOP=true
        ;;
      --skip-cursor-cli)
        SKIP_CURSOR_CLI=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Opcao invalida: $1"
        ;;
    esac
    shift
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatorio nao encontrado: $1"
}

require_sudo() {
  require_cmd sudo
}

is_ubuntu() {
  [[ -f /etc/os-release ]] && grep -qi '^ID=ubuntu\|ubuntu' /etc/os-release
}

is_wsl() {
  grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

has_wslg() {
  [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]
}

apt_install() {
  sudo apt install -y "$@"
}

install_base_deps() {
  log "Instalando dependencias base..."
  sudo apt update
  apt_install software-properties-common curl wget ca-certificates gnupg apt-transport-https
  success "Dependencias base instaladas"
}

install_git() {
  if [[ "$SKIP_GIT" == true ]]; then
    warn "Pulando instalacao do Git"
    return
  fi

  if command -v git >/dev/null 2>&1; then
    success "Git ja instalado: $(git --version)"
    return
  fi

  log "Instalando Git..."
  apt_install git
  success "Git instalado: $(git --version)"
}

install_erlang_elixir() {
  if [[ "$SKIP_ELIXIR" == true ]]; then
    warn "Pulando instalacao de Erlang/Elixir"
    return
  fi

  if command -v erl >/dev/null 2>&1 && command -v elixir >/dev/null 2>&1; then
    success "Erlang e Elixir ja instalados"
    erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
    elixir --version
    return
  fi

  log "Adicionando PPA do RabbitMQ para Erlang mais recente..."
  sudo add-apt-repository -y ppa:rabbitmq/rabbitmq-erlang
  sudo apt update

  log "Instalando Erlang e Elixir..."
  apt_install erlang elixir

  local otp_version
  otp_version="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"

  if [["${otp_version}" -lt 28]]; then
	  warn "OTP $otp_version instalado. Voce queria OTP 28+."
  	  warn "Podemos ajustar manualmente depois."
  else
	  success "TOP ${otp_version} OK"
  fi

  success "Erlang e Elixir instalados"
  erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
  elixir --version
}

install_cursor_desktop() {
  if [[ "$SKIP_CURSOR_DESKTOP" == true ]]; then
    warn "Pulando instalacao do Cursor Desktop"
    return
  fi

  if command -v cursor >/dev/null 2>&1; then
    success "Cursor ja encontrado em: $(command -v cursor)"
    return
  fi

  if is_wsl && ! has_wslg; then
    warn "WSLg/Display nao detectado. Vou pular o Cursor Desktop por enquanto."
    warn "Depois voce pode instalar manualmente ou rerodar com ambiente grafico disponivel."
    return
  fi

  log "Baixando Cursor Desktop (.deb)..."
  local tmp_deb="/tmp/cursor_latest_amd64.deb"
  wget -O "$tmp_deb" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/3.1"

  log "Instalando Cursor Desktop..."
  sudo apt install -y "$tmp_deb"
  success "Cursor Desktop instalado"
}

install_cursor_cli() {
  if [[ "$SKIP_CURSOR_CLI" == true ]]; then
    warn "Pulando instalacao do Cursor CLI"
    return
  fi

  if command -v cursor-agent >/dev/null 2>&1; then
    success "Cursor CLI ja instalado: $(command -v cursor-agent)"
    return
  fi

  log "Instalando Cursor CLI..."
  curl -fsSL https://cursor.com/install | bash
  success "Cursor CLI instalado (ou script executado com sucesso)"
}

print_validation() {
  cat <<'EOF'

Validacoes uteis:

  git --version
  erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
  elixir --version
  which cursor || true
  which cursor-agent || true

Se algum comando nao aparecer imediatamente:

  source ~/.bashrc
  hash -r

Para abrir o Cursor no diretorio atual:

  cursor .

EOF
}

main() {
  parse_args "$@"
  require_sudo

  if ! is_ubuntu; then
    warn "Este script foi pensado para Ubuntu. Pode funcionar em Debian-like, mas nao foi testado fora do Ubuntu."
  fi

  if is_wsl; then
    success "WSL detectado"
  else
    warn "WSL nao detectado. Seguirei mesmo assim."
  fi

  install_base_deps
  install_git
  install_erlang_elixir
  install_cursor_desktop
  install_cursor_cli
  print_validation
}

main "$@"

