# Monitoreo del CTF Tarreo (Wazuh host + egreso IA)

Kit para el **host del evento** (64 GB RAM, etc.). Cubre dos cosas que se
pidieron: (1) **monitoreo de host** del RCE/LFI y la **lectura de flags**, y
(2) **bloqueo de egreso a servicios de IA**.

> No es necesario para que el CTF funcione; es la capa de observabilidad/control.
> Todo esto se despliega en el host real (requiere root y Wazuh instalado).

## 1. Qué detecta (plano de host, vía auditd + Wazuh)

El agente Wazuh corre en el **host** (kernel compartido ⇒ ve también los procesos
y accesos a archivos **dentro de los contenedores**):

| Señal | Cómo | Regla Wazuh |
|---|---|---|
| **Captura de flag** (lectura del archivo) | auditd watch de lectura sobre el inodo de la flag (bind-mount) | `100100`, `100111` |
| **RCE** (ejecución de `sh/nc/python/...`) | auditd execve | `100110` |
| **Reverse shell** (conexión saliente de una shell) | auditd connect | `100120` |
| **Webshell** (`.jsp`, `sess_*`, `.php` nuevos) | Wazuh FIM realtime en los webroots | `100130` |

### Despliegue (en el host)
```bash
# a) auditd
sudo cp monitoring/audit-ctf.rules /etc/audit/rules.d/ctf.rules
#    EDITA la ruta de flags dentro del archivo a la real (BASE/flags)
sudo augenrules --load && sudo systemctl enable --now auditd

# b) Agente Wazuh: añade los bloques de ossec-agent-snippet.conf a
#    /var/ossec/etc/ossec.conf  (ajusta rutas) y reinicia:
sudo systemctl restart wazuh-agent

# c) Manager Wazuh: reglas de alerta
sudo cp monitoring/local_rules.xml /var/ossec/etc/rules/local_rules.xml
sudo systemctl restart wazuh-manager
```
Las alertas salen en el dashboard de Wazuh (filtra por grupo `ctf`).

### Recursos
Con 64 GB el stack Wazuh completo (manager + indexer + dashboard ≈ 3–4 GB) convive
sin problema con CTFd y los 25 contenedores. Si algún día va justo: sube el heap del
indexer o limita RAM por contenedor.

## 2. Bloqueo de egreso a IA

`scripts/block_ai_egress.sh` + `monitoring/ai-domains.txt`: sinkhole DNS con dnsmasq
(cada dominio de IA → `0.0.0.0`).

```bash
scripts/block_ai_egress.sh print          # ver qué generaría (sin root)
sudo scripts/block_ai_egress.sh apply       # instalar sinkhole + recargar dnsmasq
scripts/block_ai_egress.sh test claude.ai   # comprobar
sudo scripts/block_ai_egress.sh clear        # quitar
```

**REQUISITO:** los participantes deben usar **este host como DNS** (entrégalo por
DHCP, option 6). **Limitaciones honestas:** DoH, DNS hardcodeado, VPN o datos móviles
lo saltan. Es un **disuasivo**, no una garantía — combínalo con:
- Bloquear a nivel de firewall los resolvers DoH conocidos (están en la lista).
- **Proctoring humano** (la única forma fiable de hacer cumplir "no IA").
- Que la red del evento sea cerrada y el internet (si hay) pase por tu gateway.

> Importante: Wazuh/host **no ve las laptops de los participantes**; no puede saber si
> alguien abre una IA en su equipo. El control de IA es de **red** (egreso) + proctoring.
