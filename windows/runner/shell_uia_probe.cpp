#include "shell_uia_probe.h"

#include <wrl/client.h>

namespace shell_uia_probe {
using Microsoft::WRL::ComPtr;

bool IsWritableEdit(bool focusable, bool focused, bool read_only) {
  return !read_only && (focusable || focused);
}

namespace {
constexpr int kMaxCandidates = 4096;
class PhysicalCoordinates {
 public:
  PhysicalCoordinates() : previous_(SetThreadDpiAwarenessContext(
      DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {}
  ~PhysicalCoordinates() {
    if (previous_) SetThreadDpiAwarenessContext(previous_);
  }
 private:
  DPI_AWARENESS_CONTEXT previous_;
};

bool CachedWritableEdit(IUIAutomationElement* element, HRESULT& error) {
  BOOL focusable = FALSE, focused = FALSE;
  error = element->get_CachedIsKeyboardFocusable(&focusable);
  if (FAILED(error)) return true;
  error = element->get_CachedHasKeyboardFocus(&focused);
  if (FAILED(error)) return true;
  VARIANT read_only;
  VariantInit(&read_only);
  error = element->GetCachedPropertyValue(UIA_ValueIsReadOnlyPropertyId, &read_only);
  const bool immutable = SUCCEEDED(error) && read_only.vt == VT_BOOL &&
                         read_only.boolVal == VARIANT_TRUE;
  VariantClear(&read_only);
  return IsWritableEdit(focusable != FALSE, focused != FALSE, immutable);
}
}  // namespace

Result Probe(IUIAutomation* automation, HWND source, DWORD process, POINT point,
             const std::atomic<bool>& stopping) {
  Result result;
  if (!automation || stopping.load()) return result;
  PhysicalCoordinates physical;
  ComPtr<IUIAutomationCacheRequest> cache;
  result.error = automation->CreateCacheRequest(&cache);
  if (FAILED(result.error)) { result.reason = "uia_cache_unavailable"; return result; }
  const PROPERTYID properties[] = {UIA_ProcessIdPropertyId, UIA_ControlTypePropertyId,
       UIA_BoundingRectanglePropertyId, UIA_IsOffscreenPropertyId,
       UIA_IsKeyboardFocusablePropertyId, UIA_HasKeyboardFocusPropertyId,
       UIA_ValueIsReadOnlyPropertyId};
  for (const auto property : properties) {
    result.error = cache->AddProperty(property);
    if (FAILED(result.error)) { result.reason = "uia_cache_property_failed"; return result; }
  }
  result.error = cache->put_TreeScope(TreeScope_Element);
  if (FAILED(result.error)) return result;
  ComPtr<IUIAutomationElement> root;
  result.error = automation->ElementFromHandleBuildCache(source, cache.Get(), &root);
  if (FAILED(result.error) || !root) {
    result.reason = "uia_source_unavailable";
    return result;
  }
  result.error = root->get_CachedProcessId(&result.process);
  if (FAILED(result.error) || static_cast<DWORD>(result.process) != process) {
    result.reason = "uia_source_process_mismatch";
    return result;
  }
  CONTROLTYPEID root_type = 0;
  result.error = root->get_CachedControlType(&root_type);
  if (FAILED(result.error)) return result;
  if (root_type == UIA_EditControlTypeId && CachedWritableEdit(root.Get(), result.error)) {
    result.reason = "uia_writable_edit";
    result.definitive = true;
    return result;
  }
  // Find only item geometry and edit state. Other panes, toolbar buttons and
  // navigation tree nodes cannot become file candidates.
  ComPtr<IUIAutomationCondition> item, row, edit, items, types, visible, condition;
  VARIANT type;
  VariantInit(&type);
  type.vt = VT_I4;
  type.lVal = UIA_ListItemControlTypeId;
  result.error = automation->CreatePropertyCondition(UIA_ControlTypePropertyId, type, &item);
  if (FAILED(result.error)) return result;
  type.lVal = UIA_DataItemControlTypeId;
  result.error = automation->CreatePropertyCondition(UIA_ControlTypePropertyId, type, &row);
  if (FAILED(result.error)) return result;
  type.lVal = UIA_EditControlTypeId;
  result.error = automation->CreatePropertyCondition(UIA_ControlTypePropertyId, type, &edit);
  if (FAILED(result.error)) return result;
  result.error = automation->CreateOrCondition(item.Get(), row.Get(), &items);
  if (FAILED(result.error)) return result;
  result.error = automation->CreateOrCondition(items.Get(), edit.Get(), &types);
  if (FAILED(result.error)) return result;
  VARIANT visible_value;
  VariantInit(&visible_value);
  visible_value.vt = VT_BOOL;
  visible_value.boolVal = VARIANT_FALSE;
  result.error = automation->CreatePropertyCondition(UIA_IsOffscreenPropertyId,
                                                      visible_value, &visible);
  if (FAILED(result.error)) return result;
  result.error = automation->CreateAndCondition(types.Get(), visible.Get(), &condition);
  if (FAILED(result.error)) return result;
  ComPtr<IUIAutomationElementArray> candidates;
  result.error = root->FindAllBuildCache(TreeScope_Descendants, condition.Get(),
                                        cache.Get(), &candidates);
  if (FAILED(result.error) || !candidates) {
    result.reason = "uia_source_query_failed";
    return result;
  }
  result.error = candidates->get_Length(&result.candidates);
  if (FAILED(result.error) || result.candidates > kMaxCandidates) {
    result.reason = "uia_source_query_limit";
    return result;
  }
  bool item_at_point = false;
  for (int index = 0; index < result.candidates && !stopping.load(); ++index) {
    ComPtr<IUIAutomationElement> candidate;
    result.error = candidates->GetElement(index, &candidate);
    if (FAILED(result.error) || !candidate) return result;
    int owner = 0;
    BOOL offscreen = FALSE;
    RECT bounds = {};
    CONTROLTYPEID candidate_type = 0;
    if (FAILED(candidate->get_CachedProcessId(&owner)) ||
        FAILED(candidate->get_CachedIsOffscreen(&offscreen)) ||
        FAILED(candidate->get_CachedBoundingRectangle(&bounds)) ||
        FAILED(candidate->get_CachedControlType(&candidate_type))) {
      result.reason = "uia_candidate_properties_failed";
      return result;
    }
    if (static_cast<DWORD>(owner) != process || offscreen || !PtInRect(&bounds, point))
      continue;
    if (candidate_type == UIA_EditControlTypeId) {
      if (CachedWritableEdit(candidate.Get(), result.error)) {
        result.reason = "uia_writable_edit";
        result.definitive = true;
        return result;
      }
    } else {
      item_at_point = true;
    }
  }
  if (stopping.load()) { result.reason = "uia_query_cancelled"; return result; }
  result.is_item = item_at_point;
  result.definitive = true;
  result.reason = item_at_point ? "file_item_uia_source_view" : "uia_source_without_file_item";
  return result;
}
}  // namespace shell_uia_probe
