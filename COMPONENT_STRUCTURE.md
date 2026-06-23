# Component Structure

## Design Goal

Build a work-focused SaaS interface for repeated daily use. The UI should be dense, clear, fast, and predictable.

Do not build a marketing landing page as the primary product screen.

## Component Layers

```text
src/components
├── ui
├── layout
├── data
├── forms
├── feedback
└── navigation
```

## Base UI Components

```text
src/components/ui
├── button.tsx
├── input.tsx
├── textarea.tsx
├── select.tsx
├── checkbox.tsx
├── badge.tsx
├── table.tsx
├── tabs.tsx
├── dialog.tsx
├── dropdown-menu.tsx
├── tooltip.tsx
├── card.tsx
├── skeleton.tsx
└── toast.tsx
```

Use cards only for repeated items, modals, and genuinely framed tool surfaces. Avoid nested cards.

## Layout Components

```text
src/components/layout
├── app-shell.tsx
├── app-sidebar.tsx
├── app-header.tsx
├── org-switcher.tsx
├── user-menu.tsx
├── page-header.tsx
└── admin-shell.tsx
```

## Data Components

```text
src/components/data
├── data-table.tsx
├── empty-state.tsx
├── metric-strip.tsx
├── status-filter.tsx
├── date-range-filter.tsx
└── pagination.tsx
```

## Feature Components

### Organizations

```text
src/features/organizations/components
├── organization-settings-form.tsx
├── organization-status-badge.tsx
├── member-list.tsx
└── role-badge.tsx
```

### Contacts

```text
src/features/contacts/components
├── contact-table.tsx
├── contact-form.tsx
├── contact-detail-header.tsx
└── contact-timeline.tsx
```

### Leads

```text
src/features/leads/components
├── lead-table.tsx
├── lead-form.tsx
├── lead-status-select.tsx
├── lead-source-badge.tsx
└── lead-detail-panel.tsx
```

### Activities

```text
src/features/activities/components
├── activity-list.tsx
├── activity-form.tsx
├── activity-type-icon.tsx
└── activity-timeline-item.tsx
```

### Knowledge Base

```text
src/features/knowledge-base/components
├── document-upload.tsx
├── document-table.tsx
├── document-status-badge.tsx
├── knowledge-search.tsx
└── search-result-list.tsx
```

### AI Assistant

```text
src/features/assistant/components
├── conversation-list.tsx
├── chat-thread.tsx
├── message-bubble.tsx
├── message-composer.tsx
├── retrieved-context-panel.tsx
└── model-status-indicator.tsx
```

### Dashboard

```text
src/features/dashboard/components
├── lead-summary.tsx
├── activity-summary.tsx
├── usage-summary.tsx
├── recent-leads.tsx
└── recent-activities.tsx
```

### Super Admin

```text
src/features/super-admin/components
├── organization-admin-table.tsx
├── organization-status-form.tsx
├── user-admin-table.tsx
├── trial-controls.tsx
└── audit-log-table.tsx
```

## UX Rules

- Tables are the default for operational lists.
- Forms should be short and task-specific.
- Every destructive action requires confirmation.
- Every loading route gets a skeleton.
- Every empty list gets a useful empty state.
- Use role-aware disabled states and clear forbidden messages.
- Use icons for common actions when available.
- Keep dashboard cards compact and scan-friendly.

## Permission-Aware Components

Components must not be the source of truth for security. They may hide controls for usability, but API routes and server actions must enforce permissions.

Role behavior:

- `organization_owner`: full organization management.
- `executive`: manage CRM, knowledge, assistant; view usage.
- `analyst`: create/update CRM records, use assistant, search knowledge.
- `viewer`: read-only access.
- `super_admin`: global admin routes only.

## Accessibility

- Keyboard accessible dialogs and menus.
- Visible focus states.
- Labels for all inputs.
- ARIA labels for icon-only buttons.
- Table actions reachable by keyboard.

