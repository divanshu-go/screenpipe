"use client";

import { useState, useEffect, useCallback } from "react";
import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { commands } from "@/lib/utils/tauri";
import { openPermissionSettingsWithFlow, requestPermissionWithFlow } from "@/lib/utils/permission-flow";
import { usePlatform } from "@/lib/hooks/use-platform";
import { useTauriEvent } from "@/lib/hooks/use-tauri-event";

interface PermissionState {
  screenOk: boolean;
  micOk: boolean;
  accessibilityOk: boolean;
}

/**
 * Persistent inline banner shown at the top of the main UI when permissions are missing.
 * Cannot be permanently dismissed — only goes away when permissions are granted.
 */
export function PermissionBanner() {
  const [permissions, setPermissions] = useState<PermissionState | null>(null);
  // Screen denial reported by the engine's capture modules (ScreenCaptureKit
  // ground truth). The polled doPermissionsCheck below rides
  // CGPreflightScreenCaptureAccess, whose per-process cached answer can stay
  // "granted" after macOS actually revoked capture (e.g. macOS 26 monthly
  // re-approval) — the exact silent-gap scenario of #4819/#4726.
  const [engineScreenDenied, setEngineScreenDenied] = useState(false);

  const { isMac } = usePlatform();

  const checkPermissions = useCallback(async () => {
    if (!isMac) return;
    try {
      const perms = await commands.doPermissionsCheck(false);
      const screenOk = perms.screenRecording === "granted" || perms.screenRecording === "notNeeded";
      const micOk = perms.microphone === "granted" || perms.microphone === "notNeeded";
      const accessibilityOk = perms.accessibility === "granted" || perms.accessibility === "notNeeded";
      setPermissions({ screenOk, micOk, accessibilityOk });

    } catch {
      // ignore errors
    }
  }, [isMac]);

  // Check on mount and poll every 5 seconds
  useEffect(() => {
    checkPermissions();
    const interval = setInterval(checkPermissions, 5000);
    return () => clearInterval(interval);
  }, [checkPermissions]);

  // Also listen for permission-lost events for instant response
  useTauriEvent("permission-lost", (event) => {
    const payload = event.payload as { screen_recording?: boolean } | undefined;
    if (payload?.screen_recording) setEngineScreenDenied(true);
    checkPermissions();
  });

  // permission_needed re-fires periodically while screen recording stays
  // denied (#4819) — including when the denial predates this webview.
  useTauriEvent("permission_needed", (event) => {
    const payload = event.payload as { kind?: string } | undefined;
    if (payload?.kind === "screen_recording") setEngineScreenDenied(true);
    checkPermissions();
  });

  useTauriEvent("permission-restored", (event) => {
    const payload = event.payload as { kind?: string } | undefined;
    if (payload?.kind === "screen_recording") setEngineScreenDenied(false);
    checkPermissions();
  });

  // Don't render on non-Mac or while loading
  if (!isMac || !permissions) return null;

  const screenOk = permissions.screenOk && !engineScreenDenied;

  // Don't render if all permissions are granted
  if (screenOk && permissions.micOk && permissions.accessibilityOk) return null;



  const missingPerms: string[] = [];
  if (!screenOk) missingPerms.push("screen recording");
  if (!permissions.micOk) missingPerms.push("microphone");
  if (!permissions.accessibilityOk) missingPerms.push("accessibility");

  return (
    <div className="w-full bg-destructive border-b-2 border-destructive px-4 py-3 flex items-center justify-between gap-3 z-50">
      <div className="flex items-center gap-3 min-w-0">
        <AlertTriangle className="h-5 w-5 text-destructive-foreground shrink-0" />
        <div className="flex items-center gap-2 min-w-0">
          <span className="font-semibold text-destructive-foreground text-base">
            {missingPerms.join(" & ")} disabled
          </span>
          <span className="text-destructive-foreground/80 hidden sm:inline text-sm">
            — recording is paused
          </span>
        </div>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        <Button
          variant="secondary"
          size="sm"
          className="h-8 px-4 text-sm font-medium"
          onClick={async () => {
            // Try requestPermission first — this shows the native macOS dialog
            // (e.g. mic prompt, accessibility prompt). If the permission was already
            // denied, it falls back to opening System Settings internally.
            try {
              if (!screenOk) await requestPermissionWithFlow("screenRecording");
              else if (!permissions.micOk) await commands.requestPermission("microphone");
              else if (!permissions.accessibilityOk) await requestPermissionWithFlow("accessibility");
            } catch {
              // fallback to opening settings directly
              if (!screenOk) await openPermissionSettingsWithFlow("screenRecording");
              else if (!permissions.micOk) await commands.openPermissionSettings("microphone");
              else if (!permissions.accessibilityOk) await openPermissionSettingsWithFlow("accessibility");
            }
          }}
        >
          fix permissions
        </Button>

      </div>
    </div>
  );
}
