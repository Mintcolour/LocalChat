#ifndef RUNNER_FIREWALL_MANAGER_H_
#define RUNNER_FIREWALL_MANAGER_H_

#include <windows.h>

namespace firewall {

struct FirewallStatus {
  bool udp_configured = false;
  bool tcp_configured = false;
  long error_code = 0;
};

FirewallStatus GetStatus();
DWORD RunElevatedRepair(HWND owner);
int ConfigureRules();

}  // namespace firewall

#endif  // RUNNER_FIREWALL_MANAGER_H_
