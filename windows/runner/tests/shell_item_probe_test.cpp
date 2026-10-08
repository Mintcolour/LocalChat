#include "../shell_item_probe.h"

#include <wrl/client.h>
#include <iostream>

using Microsoft::WRL::ComPtr;

// Test the two MSAA result shapes without interacting with the user's desktop.
class AccessibleItem final : public IAccessible {
 public:
  explicit AccessibleItem(LONG role) : role_(role) {}
  ComPtr<IAccessible> child;
  HRESULT hit_result = S_OK;
  HRESULT role_result = S_OK;
  bool blank = false;

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (iid != __uuidof(IUnknown) && iid != __uuidof(IDispatch) &&
        iid != __uuidof(IAccessible)) return E_NOINTERFACE;
    *result = static_cast<IAccessible*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG remaining = --refs_;
    if (!remaining) delete this;
    return remaining;
  }
  HRESULT STDMETHODCALLTYPE accHitTest(long, long, VARIANT* hit) override {
    VariantInit(hit);
    if (hit_result != S_OK) return hit_result;
    if (blank) return S_OK;
    if (child) {
      hit->vt = VT_DISPATCH;
      hit->pdispVal = child.Get();
      child->AddRef();
    } else {
      hit->vt = VT_I4;
      hit->lVal = 1;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_accRole(VARIANT, VARIANT* role) override {
    VariantInit(role);
    if (role_result != S_OK) return role_result;
    role->vt = VT_I4;
    role->lVal = role_;
    return S_OK;
  }
#define UNUSED_METHOD(name, parameters) \
  HRESULT STDMETHODCALLTYPE name parameters override { return E_NOTIMPL; }
  UNUSED_METHOD(GetTypeInfoCount, (UINT*))
  UNUSED_METHOD(GetTypeInfo, (UINT, LCID, ITypeInfo**))
  UNUSED_METHOD(GetIDsOfNames, (REFIID, LPOLESTR*, UINT, LCID, DISPID*))
  UNUSED_METHOD(Invoke, (DISPID, REFIID, LCID, WORD, DISPPARAMS*, VARIANT*, EXCEPINFO*, UINT*))
  UNUSED_METHOD(get_accParent, (IDispatch**))
  UNUSED_METHOD(get_accChildCount, (long*))
  UNUSED_METHOD(get_accChild, (VARIANT, IDispatch**))
  UNUSED_METHOD(get_accName, (VARIANT, BSTR*))
  UNUSED_METHOD(get_accValue, (VARIANT, BSTR*))
  UNUSED_METHOD(get_accDescription, (VARIANT, BSTR*))
  UNUSED_METHOD(get_accState, (VARIANT, VARIANT*))
  UNUSED_METHOD(get_accHelp, (VARIANT, BSTR*))
  UNUSED_METHOD(get_accHelpTopic, (BSTR*, VARIANT, long*))
  UNUSED_METHOD(get_accKeyboardShortcut, (VARIANT, BSTR*))
  UNUSED_METHOD(get_accFocus, (VARIANT*))
  UNUSED_METHOD(get_accSelection, (VARIANT*))
  UNUSED_METHOD(get_accDefaultAction, (VARIANT, BSTR*))
  UNUSED_METHOD(accSelect, (long, VARIANT))
  UNUSED_METHOD(accLocation, (long*, long*, long*, long*, VARIANT))
  UNUSED_METHOD(accNavigate, (long, VARIANT, VARIANT*))
  UNUSED_METHOD(accDoDefaultAction, (VARIANT))
  UNUSED_METHOD(put_accName, (VARIANT, BSTR))
  UNUSED_METHOD(put_accValue, (VARIANT, BSTR))
#undef UNUSED_METHOD
 private:
  ULONG refs_ = 1;
  LONG role_;
};

int wmain() {
  const POINT point = {40, 40};
  int checks = 0;
  int failures = 0;
  const auto expect = [&](bool condition) {
    ++checks;
    if (!condition) ++failures;
  };
  ComPtr<AccessibleItem> item;
  item.Attach(new AccessibleItem(ROLE_SYSTEM_LISTITEM));
  ComPtr<AccessibleItem> pane;
  pane.Attach(new AccessibleItem(ROLE_SYSTEM_LIST));
  ComPtr<AccessibleItem> edit;
  edit.Attach(new AccessibleItem(ROLE_SYSTEM_TEXT));
  expect(!shell_item_probe::IsFileItem(static_cast<IAccessible*>(nullptr), point));
  expect(shell_item_probe::IsFileItem(item.Get(), point));
  expect(!shell_item_probe::IsFileItem(pane.Get(), point));
  expect(!shell_item_probe::IsFileItem(edit.Get(), point));
  pane->child = item;
  expect(shell_item_probe::IsFileItem(pane.Get(), point));
  pane->child = edit;
  expect(!shell_item_probe::IsFileItem(pane.Get(), point));
  pane->child.Reset();
  item->blank = true;
  expect(!shell_item_probe::IsFileItem(item.Get(), point));
  item->blank = false;
  item->hit_result = S_FALSE;
  expect(!shell_item_probe::IsFileItem(item.Get(), point));
  item->hit_result = S_OK;
  item->role_result = E_FAIL;
  expect(!shell_item_probe::IsFileItem(item.Get(), point));
  std::cout << checks - failures << '/' << checks
            << " Shell item compatibility checks passed.\n";
  return failures ? 1 : 0;
}
