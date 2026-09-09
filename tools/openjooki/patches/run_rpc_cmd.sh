#! /bin/ash
# Neutralise par OpenJooki : execution de commandes distantes desactivee (securite).
logger -s "OpenJooki: remote command execution disabled"
/jooki/bin/esp32_cmd set_remote_command_execution_result "DISABLED BY OPENJOOKI" 2>/dev/null || true
exit 1
