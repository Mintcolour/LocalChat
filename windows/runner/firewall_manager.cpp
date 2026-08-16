#include "firewall_manager.h"

#include <netfw.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace {

constexpr wchar_t kUdpRuleName[] = L"LocalChat LAN UDP Discovery";
constexpr wchar_t kTcpRuleName[] = L"LocalChat LAN TCP Transfer";
constexpr wchar_t kRuleGroup[] = L"LocalChat";
constexpr wchar_t kUdpPorts[] = L"45871-45875,59641-59645,61071-61075";
constexpr wchar_t kLocalSubnet[] = L"LocalSubnet";

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    const DWORD size =
        GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (size == 0) {
      return L"";
    }
    if (size < buffer.size() - 1) {
      return std::wstring(buffer.data(), size);
    }
    buffer.resize(buffer.size() * 2);
  }
}

HRESULT OpenRules(INetFwRules** rules) {
  if (rules == nullptr) {
    return E_POINTER;
  }
  *rules = nullptr;
  INetFwPolicy2* policy = nullptr;
  HRESULT result = CoCreateInstance(__uuidof(NetFwPolicy2), nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&policy));
  if (FAILED(result)) {
    return result;
  }
  result = policy->get_Rules(rules);
  policy->Release();
  return result;
}

bool IsRuleConfigured(INetFwRules* rules, const wchar_t* name, long protocol,
                      const wchar_t* expected_local_ports,
                      const std::wstring& executable_path) {
  if (rules == nullptr) {
    return false;
  }
  BSTR rule_name = SysAllocString(name);
  INetFwRule* rule = nullptr;
  const HRESULT result = rules->Item(rule_name, &rule);
  SysFreeString(rule_name);
  if (FAILED(result) || rule == nullptr) {
    return false;
  }

  VARIANT_BOOL enabled = VARIANT_FALSE;
  long actual_protocol = 0;
  NET_FW_RULE_DIRECTION direction = NET_FW_RULE_DIR_MAX;
  NET_FW_ACTION action = NET_FW_ACTION_BLOCK;
  long profiles = 0;
  BSTR application = nullptr;
  BSTR local_ports = nullptr;
  BSTR remote_addresses = nullptr;
  rule->get_Enabled(&enabled);
  rule->get_Protocol(&actual_protocol);
  rule->get_Direction(&direction);
  rule->get_Action(&action);
  rule->get_Profiles(&profiles);
  rule->get_ApplicationName(&application);
  rule->get_LocalPorts(&local_ports);
  rule->get_RemoteAddresses(&remote_addresses);
  const bool path_matches =
      application != nullptr &&
      _wcsicmp(application, executable_path.c_str()) == 0;
  const bool ports_match =
      expected_local_ports == nullptr ||
      (local_ports != nullptr &&
       _wcsicmp(local_ports, expected_local_ports) == 0);
  const bool remote_matches =
      remote_addresses != nullptr &&
      _wcsicmp(remote_addresses, kLocalSubnet) == 0;
  constexpr long kRequiredProfiles =
      NET_FW_PROFILE2_DOMAIN | NET_FW_PROFILE2_PRIVATE | NET_FW_PROFILE2_PUBLIC;
  const bool profiles_match =
      (profiles & kRequiredProfiles) == kRequiredProfiles;
  if (application != nullptr) {
    SysFreeString(application);
  }
  if (local_ports != nullptr) {
    SysFreeString(local_ports);
  }
  if (remote_addresses != nullptr) {
    SysFreeString(remote_addresses);
  }
  rule->Release();
  return enabled == VARIANT_TRUE && actual_protocol == protocol &&
         direction == NET_FW_RULE_DIR_IN && action == NET_FW_ACTION_ALLOW &&
         path_matches && ports_match && remote_matches && profiles_match;
}

HRESULT AddRule(INetFwRules* rules, const wchar_t* name, long protocol,
                const wchar_t* local_ports,
                const std::wstring& executable_path) {
  BSTR rule_name = SysAllocString(name);
  rules->Remove(rule_name);

  INetFwRule* rule = nullptr;
  HRESULT result = CoCreateInstance(__uuidof(NetFwRule), nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&rule));
  if (FAILED(result)) {
    SysFreeString(rule_name);
    return result;
  }

  BSTR description =
      SysAllocString(L"Allow LocalChat communication on the local subnet.");
  BSTR group = SysAllocString(kRuleGroup);
  BSTR application = SysAllocString(executable_path.c_str());
  BSTR remote_addresses = SysAllocString(kLocalSubnet);
  BSTR ports =
      local_ports == nullptr ? nullptr : SysAllocString(local_ports);

  result = rule->put_Name(rule_name);
  if (SUCCEEDED(result)) result = rule->put_Description(description);
  if (SUCCEEDED(result)) result = rule->put_Grouping(group);
  if (SUCCEEDED(result)) result = rule->put_ApplicationName(application);
  if (SUCCEEDED(result)) result = rule->put_Protocol(protocol);
  if (SUCCEEDED(result) && ports != nullptr) {
    result = rule->put_LocalPorts(ports);
  }
  if (SUCCEEDED(result)) {
    result = rule->put_RemoteAddresses(remote_addresses);
  }
  if (SUCCEEDED(result)) result = rule->put_Direction(NET_FW_RULE_DIR_IN);
  if (SUCCEEDED(result)) result = rule->put_Action(NET_FW_ACTION_ALLOW);
  if (SUCCEEDED(result)) result = rule->put_Profiles(NET_FW_PROFILE2_ALL);
  if (SUCCEEDED(result)) result = rule->put_EdgeTraversal(VARIANT_FALSE);
  if (SUCCEEDED(result)) result = rule->put_Enabled(VARIANT_TRUE);
  if (SUCCEEDED(result)) result = rules->Add(rule);

  if (ports != nullptr) SysFreeString(ports);
  SysFreeString(remote_addresses);
  SysFreeString(application);
  SysFreeString(group);
  SysFreeString(description);
  SysFreeString(rule_name);
  rule->Release();
  return result;
}

}  // namespace

namespace firewall {

FirewallStatus GetStatus() {
  FirewallStatus status;
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    status.error_code = GetLastError();
    return status;
  }
  INetFwRules* rules = nullptr;
  const HRESULT result = OpenRules(&rules);
  if (FAILED(result)) {
    status.error_code = result;
    return status;
  }
  status.udp_configured = IsRuleConfigured(
      rules, kUdpRuleName, NET_FW_IP_PROTOCOL_UDP, kUdpPorts, executable_path);
  status.tcp_configured = IsRuleConfigured(
      rules, kTcpRuleName, NET_FW_IP_PROTOCOL_TCP, nullptr, executable_path);
  rules->Release();
  return status;
}

int ConfigureRules() {
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    return 1;
  }
  INetFwRules* rules = nullptr;
  HRESULT result = OpenRules(&rules);
  if (FAILED(result)) {
    return 1;
  }
  result = AddRule(rules, kUdpRuleName, NET_FW_IP_PROTOCOL_UDP, kUdpPorts,
                   executable_path);
  if (SUCCEEDED(result)) {
    result = AddRule(rules, kTcpRuleName, NET_FW_IP_PROTOCOL_TCP, nullptr,
                     executable_path);
  }
  rules->Release();
  return SUCCEEDED(result) ? 0 : 1;
}

DWORD RunElevatedRepair(HWND owner) {
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    return GetLastError();
  }
  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask = SEE_MASK_NOCLOSEPROCESS;
  execute_info.hwnd = owner;
  execute_info.lpVerb = L"runas";
  execute_info.lpFile = executable_path.c_str();
  execute_info.lpParameters = L"--repair-firewall";
  execute_info.nShow = SW_HIDE;
  if (!ShellExecuteExW(&execute_info)) {
    return GetLastError();
  }
  WaitForSingleObject(execute_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(execute_info.hProcess, &exit_code);
  CloseHandle(execute_info.hProcess);
  return exit_code;
}

}  // namespace firewall
