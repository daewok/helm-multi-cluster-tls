# -*- sh-basic-offset: 2 -*-

MY_HELM_CONFIG_STATE="thawed"
MY_HELM_FROZEN_CONTEXT=""

function helm-watcher {
  local pid_file="/run/user/${UID}/helm-watch-for-kube-context-change.pid"
  case "$1" in
    status )
      if [ -e "${pid_file}" ]; then
        local pid="$(cat ${pid_file})"
        echo $pid
        if ps -p $pid > /dev/null; then
          echo "running"
        else
          echo "stopped"
          return 1
        fi
      else
        echo "stopped"
        return 1
      fi
      ;;
    start )
      if ! helm-watcher status > /dev/null; then
        start-stop-daemon -S -p "${pid_file}" -b -m helm-watch-for-kube-context-change
      fi
      ;;
    stop )
      start-stop-daemon -K -p "${pid_file}" helm-watch-for-kube-context-change
      ;;
  esac
}

function my-helm-freeze-state {
  if [ "x${MY_HELM_CONFIG_STATE}" = "xfrozen" ]; then
    exit 0
  fi

  MY_HELM_CONFIG_STATE="frozen"
  MY_HELM_FROZEN_CONTEXT="$(kubectl config view -o=jsonpath='{.current-context}')"

  local helm_home=$(command helm home)

  export TILLER_NAMESPACE="$(helm-ns)"

  if [ -e "${helm_home}/key.pem" ]; then
    export HELM_TLS_ENABLE="true"
    export HELM_TLS_CA_CERT=$(readlink -f "${helm_home}/ca.pem")
    export HELM_TLS_CERT=$(readlink -f "${helm_home}/cert.pem")
    export HELM_TLS_KEY=$(readlink -f "${helm_home}/key.pem")
  else
    export HELM_TLS_ENABLE="false"
  fi
}

function my-helm-thaw-state {
  MY_HELM_CONFIG_STATE="thawed"
  MY_HELM_FROZEN_CONTEXT=""

  unset HELM_TLS_ENABLE
  unset HELM_TLS_CA_CERT
  unset HELM_TLS_CERT
  unset HELM_TLS_KEY
  unset TILLER_NAMESPACE
}

function helm-config {
  case "$1" in
    freeze )
      my-helm-freeze-state
      ;;
    thaw )
      my-helm-thaw-state
      ;;
    check-frozen-context )
      [ "x${MY_HELM_CONFIG_STATE}" = "xthawed" ] \
        || [ "x${MY_HELM_FROZEN_CONTEXT}" = "x$(kubectl config view -o=jsonpath='{.current-context}')" ]
      ;;
    "" )
      echo "${MY_HELM_CONFIG_STATE}"
  esac
}

function helm-ns {
  case "$1" in
    "" )
      if [ -z "${TILLER_NAMESPACE}" ]; then
        cat "$(command helm home)/current_tiller_namespace"
      else
        echo "${TILLER_NAMESPACE}"
      fi
      ;;
    * )
      if [ "x${MY_HELM_CONFIG_STATE}" = "xfrozen" ]; then
        >&2 echo "Your helm config is frozen. Refusing to update global config, thaw first."
        return 1
      else
        update-helm-tls "$1"
      fi
      ;;
    set )
      MY_HELM_HELPER_STATE="local"
      ;;
    esac
}

function my-helm-run {
  local helm_home="$(command helm home)"

  if ! helm-config check-frozen-context; then
     >&2 echo "The kubectl context set when freezing helm does not match current context. Aborting."
     return 1
  fi

  if [ -e "${helm_home}/key.pem" ] && [ -z "$HELM_TLS_ENABLE" ]; then
    TILLER_NAMESPACE="$(helm-ns)" HELM_TLS_ENABLE="true" command helm "$@"
  else
    command helm "$@"
  fi
}

alias helm='my-helm-run'
