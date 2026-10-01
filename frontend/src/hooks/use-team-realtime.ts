"use client";

import { useEffect } from "react";

import { API_BASE_URL, fetchActionCableTicket } from "@/lib/api";

export function useTeamRealtime(teamId: number | null) {
  useEffect(() => {
    if (!teamId || typeof window === "undefined") {
      return;
    }

    let active = true;
    let socket: WebSocket | null = null;

    async function connect() {
      try {
        const { ticket } = await fetchActionCableTicket();
        if (!active) return;

        const cableUrl = new URL("/cable", API_BASE_URL.replace(/^http/, "ws"));
        cableUrl.searchParams.set("ticket", ticket);
        socket = new WebSocket(cableUrl);

        socket.onopen = () => {
          socket?.send(JSON.stringify({
            command: "subscribe",
            identifier: JSON.stringify({ channel: "TeamsChannel", team_id: String(teamId) }),
          }));
        };

        socket.onmessage = (event) => {
          const payload = JSON.parse(event.data);
          if (payload.type === "ping" || !payload.message) return;

          window.dispatchEvent(
            new CustomEvent("team-realtime-update", { detail: payload.message }),
          );
        };
      } catch {
        // The normal API session flow handles expired or revoked credentials.
      }
    }

    void connect();

    return () => {
      active = false;
      socket?.close();
    };
  }, [teamId]);
}
