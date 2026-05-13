const dayLabels = ["Today", "Tomorrow"];
const dayLabel = document.querySelector("[data-day-label]");
const dayPanels = Array.from(document.querySelectorAll("[data-day-panel]"));
const dayNavButtons = Array.from(document.querySelectorAll("[data-day-nav]"));

let currentDay = 0;

function renderDay() {
  if (dayLabel) {
    dayLabel.textContent = dayLabels[currentDay];
  }

  dayPanels.forEach((panel, index) => {
    const active = index === currentDay;
    panel.hidden = !active;
    panel.classList.toggle("is-active", active);
  });

  dayNavButtons.forEach((button) => {
    const direction = button.dataset.dayNav;
    if (direction === "prev") button.disabled = currentDay === 0;
    if (direction === "next") button.disabled = currentDay === dayLabels.length - 1;
  });
}

function applyMeetingState(card, state) {
  const status = card.querySelector("[data-card-status]");
  const primary = card.querySelector("[data-card-primary-action]");
  const secondary = card.querySelector("[data-card-secondary-action]");
  const join = card.querySelector("[data-card-join-action]");

  card.dataset.state = state;
  card.classList.remove("meeting-card-live", "meeting-card-scheduled", "meeting-card-joined");

  if (state === "scheduled") {
    card.classList.add("meeting-card-scheduled");
    if (status) {
      status.textContent = card.dataset.statusScheduled;
      status.className = "status status-scheduled";
    }
    if (primary) {
      primary.textContent = "Scheduled";
      primary.className = "chip chip-button chip-scheduled";
    }
    if (secondary) {
      secondary.textContent = "Cancel";
      secondary.className = "chip chip-button chip-muted";
      secondary.classList.remove("is-hidden");
    }
    if (join) {
      join.textContent = "Join now";
      join.className = "chip chip-button chip-primary";
      join.classList.remove("is-hidden");
    }
    return;
  }

  if (state === "joined") {
    card.classList.add("meeting-card-joined");
    if (status) {
      status.textContent = card.dataset.statusJoined;
      status.className = "status status-joined";
    }
    if (primary) {
      primary.textContent = "Joined";
      primary.className = "chip chip-button chip-joined";
    }
    if (secondary) {
      secondary.classList.add("is-hidden");
    }
    if (join) {
      join.classList.add("is-hidden");
    }
    return;
  }

  card.classList.add("meeting-card-live");
  if (status) {
    status.textContent = card.dataset.statusUnscheduled;
    status.className = "status status-live";
  }
  if (primary) {
    primary.textContent = "Auto-join";
    primary.className = "chip chip-button chip-muted";
  }
  if (secondary) {
    secondary.classList.add("is-hidden");
  }
  if (join) {
    join.textContent = "Join now";
    join.className = "chip chip-button chip-primary";
    join.classList.remove("is-hidden");
  }
}

function setupMeetingCard(card) {
  const chipRow = card.querySelector(".chip-row");

  // Ensure every card has a secondary (Cancel) slot — inject one if missing
  if (chipRow && !card.querySelector("[data-card-secondary-action]")) {
    const join = chipRow.querySelector("[data-card-join-action]");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "chip chip-button chip-muted is-hidden";
    btn.dataset.cardSecondaryAction = "";
    btn.textContent = "Cancel";
    chipRow.insertBefore(btn, join ?? null);
  }

  const primary = card.querySelector("[data-card-primary-action]");
  const secondary = card.querySelector("[data-card-secondary-action]");
  const join = card.querySelector("[data-card-join-action]");

  applyMeetingState(card, card.dataset.state || "unscheduled");

  primary?.addEventListener("click", () => {
    const state = card.dataset.state;
    if (state === "unscheduled") {
      applyMeetingState(card, "scheduled");
    }
  });

  secondary?.addEventListener("click", () => {
    const state = card.dataset.state;
    if (state === "scheduled") {
      applyMeetingState(card, "unscheduled");
    }
  });

  join?.addEventListener("click", () => {
    applyMeetingState(card, "joined");
    if (card.dataset.joinUrl) window.open(card.dataset.joinUrl, "_blank");
  });
}

document.querySelectorAll("[data-meeting-card]").forEach(setupMeetingCard);

document.querySelectorAll("[data-inprogress-card]").forEach((card) => {
  function transitionToJoined() {
    card.classList.remove("meeting-card-inprogress");
    card.classList.add("meeting-card-joined");
    const status = card.querySelector(".status");
    if (status) status.className = "status status-joined";
    const chipRow = card.querySelector(".chip-row");
    if (chipRow) {
      chipRow.innerHTML = `<button type="button" class="chip chip-button chip-joined">Joined</button>`;
    }
  }
  card.querySelector("[data-inprogress-mark]")?.addEventListener("click", transitionToJoined);
  card.querySelector("[data-inprogress-join]")?.addEventListener("click", () => {
    transitionToJoined();
    if (card.dataset.joinUrl) window.open(card.dataset.joinUrl, "_blank");
  });
});

document.querySelectorAll("[data-dismiss-card]").forEach((button) => {
  button.addEventListener("click", () => {
    const card = button.closest("[data-dismissable-card]");
    if (card) {
      card.classList.add("is-hidden");
    }
  });
});

document.querySelectorAll("[data-pending-accept]").forEach((button) => {
  button.addEventListener("click", () => {
    const card = button.closest("[data-pending-card]");
    if (!card) return;

    card.classList.remove("meeting-card-warm");
    card.dataset.meetingCard = "";
    card.dataset.state = "unscheduled";
    card.dataset.baseStyle = "live";
    card.dataset.statusUnscheduled = "In ~4h 30m";
    card.dataset.statusScheduled = "Auto-joining in ~4h 30m";
    card.dataset.statusJoined = "In ~4h 30m";

    const status = card.querySelector(".status");
    if (status) {
      status.textContent = "In ~4h 30m";
      status.className = "status status-live";
    }

    const actionRow = card.querySelector(".chip-row");
    if (actionRow) {
      actionRow.innerHTML = `
        <button type="button" class="chip chip-button chip-muted" data-card-primary-action>Auto-join</button>
        <button type="button" class="chip chip-button chip-primary" data-card-join-action>Join now</button>
      `;
    }

    card.removeAttribute("data-pending-card");
    setupMeetingCard(card);
  });
});

document.querySelectorAll("[data-pending-decline]").forEach((button) => {
  button.addEventListener("click", () => {
    const card = button.closest("[data-pending-card]");
    if (card) {
      card.classList.add("is-hidden");
    }
  });
});

dayNavButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (button.dataset.dayNav === "prev" && currentDay > 0) {
      currentDay -= 1;
    }

    if (button.dataset.dayNav === "next" && currentDay < dayLabels.length - 1) {
      currentDay += 1;
    }

    renderDay();
  });
});

renderDay();

// Countdown card + notification demo
(function () {
  const statusEl = document.getElementById("soon-status");
  const toast = document.getElementById("notif-toast");
  const closeBtn = document.getElementById("notif-close");
  if (!statusEl || !toast) return;

  let secsLeft = 75;
  let notifFired = false;

  const soonCard = document.getElementById("soon-card");

  function fmt(s) {
    const scheduled = soonCard?.dataset.state === "scheduled";
    const prefix = scheduled ? "Auto-joining in" : "In";
    if (s <= 0) return scheduled ? "Auto-joining now" : "Starting now";
    if (s < 60) return `${prefix} ~${s}s`;
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return rem === 0 ? `${prefix} ~${m}m` : `${prefix} ~${m}m ${rem}s`;
  }

  function showNotif() {
    toast.hidden = false;
    requestAnimationFrame(() => requestAnimationFrame(() => toast.classList.add("is-visible")));
    setTimeout(dismissNotif, 30000);
  }

  function dismissNotif() {
    toast.classList.remove("is-visible");
    setTimeout(() => { toast.hidden = true; }, 420);
  }

  closeBtn?.addEventListener("click", dismissNotif);

  toast.querySelector(".notif-join-btn")?.addEventListener("click", () => {
    const card = document.getElementById("soon-card");
    if (card) {
      applyMeetingState(card, "joined");
      if (card.dataset.joinUrl) window.open(card.dataset.joinUrl, "_blank");
    }
    clearInterval(interval);
    dismissNotif();
  });

  document.getElementById("notif-cancel")?.addEventListener("click", () => {
    const card = document.getElementById("soon-card");
    if (card) applyMeetingState(card, "unscheduled");
    dismissNotif();
  });

  const interval = setInterval(() => {
    secsLeft--;
    statusEl.textContent = fmt(secsLeft);
    statusEl.className = "status " + (soonCard?.dataset.state === "scheduled" ? "status-scheduled" : "status-live");
    if (!notifFired && secsLeft <= 60) {
      notifFired = true;
      showNotif();
    }
    if (secsLeft <= 0) clearInterval(interval);
  }, 1000);
})();

// Settings toggle
const settingsToggle = document.getElementById("settings-toggle");
const meetingsView = document.getElementById("meetings-view");
const settingsView = document.getElementById("settings-view");

settingsToggle?.addEventListener("click", () => {
  const open = !settingsView.hidden;
  settingsView.hidden = open;
  meetingsView.hidden = !open;
  settingsToggle.classList.toggle("is-active", !open);
});

// Minute steppers
function getStepperInput(key) {
  return document.querySelector(`[data-stepper-val="${key}"]`);
}

document.querySelectorAll(".stepper-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    const key = btn.dataset.stepper;
    const dir = parseInt(btn.dataset.dir, 10);
    const input = getStepperInput(key);
    const current = Math.max(0, parseInt(input.value, 10) || 0);
    input.value = Math.max(0, current + dir);
  });
});

document.querySelectorAll(".stepper-input").forEach((input) => {
  input.addEventListener("change", () => {
    const val = parseInt(input.value, 10);
    input.value = isNaN(val) || val < 0 ? 0 : val;
  });
});

// Settings toggles (show all events + calendars)
document.querySelectorAll("[data-setting-toggle]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const key = btn.dataset.settingToggle;
    const check = btn.querySelector(`[data-setting-check="${key}"]`);
    check?.classList.toggle("is-checked");
  });
});
