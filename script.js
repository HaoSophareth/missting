const dayLabels = ["Today", "Tomorrow", "Thursday, May 14"];
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
      status.className = "status status-live";
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
  });
}

document.querySelectorAll("[data-meeting-card]").forEach(setupMeetingCard);

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
