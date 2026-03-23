#!/bin/sh

# FortiCertinetes
# © 2026 JJGadgets (https://jjgadgets.tech) (https://social.jjgadgets.tech/@jj) (https://github.com/JJGadgets)
# Licensed under GNU AGPL v3.0.0
# NOT AFFILIATED WITH OR AN OFFICIAL PRODUCT/SERVICE BY FORTINET.

export FGT_HOST="${FGT_HOST:=192.168.1.99}"
export FGT_PORT="${FGT_PORT:=22}"
export FGT_USER="${FGT_USER:=admin}"

if [ -z "${FGT_VDOM}" ]; then
  FGT_CERT_CONF="config vpn certificate local"
elif [ "${FGT_VDOM}" = "global" ]; then
  FGT_CERT_CONF="config global
  config certificate local"
elif [ "${FGT_VDOM}" != "global" ]; then
  FGT_CERT_CONF="config vdom
  edit ${FGT_VDOM}
  config vpn certificate local"
fi
echo "$FGT_CERT_CONF"

kubectl get certificates -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.spec.secretName}{"\n"}{end}' | while IFS='|' read -r NAMESPACE SECRET_NAME
do
  echo
  echo "${NAMESPACE}"
  echo "${SECRET_NAME}"
  echo
  PRIVATE_KEY="$(kubectl get secrets -n "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath='{.data.tls\.key}' | base64 -d)"
  CERTIFICATE="$(kubectl get secrets -n "${NAMESPACE}" "${SECRET_NAME}" -o jsonpath='{.data.tls\.crt}' | base64 -d)"
  ssh "${FGT_USER}"@"${FGT_HOST}" -p "${FGT_PORT}" << EOF
    ${FGT_CERT_CONF}
      edit "${NAMESPACE}_${SECRET_NAME}"
        set private-key "${PRIVATE_KEY}"
        set certificate "${CERTIFICATE}"
      end
    end
EOF
done
