import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import discourseDebounce from "discourse/lib/debounce";
import { INPUT_DELAY } from "discourse/lib/environment";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { eq } from "discourse/truth-helpers";

const STATUS_META = {
  all: { icon: "list", label: "All" },
  posted: { icon: "circle-check", label: "Posted" },
  irrelevant: { icon: "circle-xmark", label: "Below threshold" },
  pending: { icon: "clock", label: "Pending" },
  filtered_out: { icon: "filter", label: "Filtered" },
  error: { icon: "triangle-exclamation", label: "Error" },
};

const STATUS_ORDER = [
  "all",
  "posted",
  "irrelevant",
  "pending",
  "error",
  "filtered_out",
];

const ROUTE_OPTIONS = ["all", "preprint", "article"];

export default class PapersTable extends Component {
  @service router;

  @tracked papers = [];
  @tracked meta = { total: 0, page: 1, total_pages: 1, status_counts: {} };
  @tracked status = "all";
  @tracked route = "all";
  @tracked search = "";
  @tracked loading = true;
  @tracked page = 1;

  constructor() {
    super(...arguments);
    this.fetch();
  }

  async fetch() {
    this.loading = true;
    try {
      const data = await ajax(
        "/admin/plugins/paper-surveyor/papers.json",
        {
          data: {
            status: this.status,
            route: this.route,
            search: this.search,
            page: this.page,
          },
        }
      );
      this.papers = data.papers || [];
      this.meta = data.meta || {
        total: 0,
        page: 1,
        total_pages: 1,
        status_counts: {},
      };
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  @action
  setStatus(status) {
    this.status = status;
    this.page = 1;
    this.fetch();
  }

  @action
  setRoute(event) {
    this.route = event.target.value;
    this.page = 1;
    this.fetch();
  }

  @action
  onSearchInput(event) {
    this.search = event.target.value;
    this.page = 1;
    discourseDebounce(this, this.fetch, INPUT_DELAY);
  }

  @action
  prevPage() {
    if (this.page > 1) {
      this.page -= 1;
      this.fetch();
    }
  }

  @action
  nextPage() {
    if (this.page < (this.meta.total_pages || 1)) {
      this.page += 1;
      this.fetch();
    }
  }

  iconFor = (status) => (STATUS_META[status] || STATUS_META.pending).icon;
  labelFor = (status) => (STATUS_META[status] || { label: status }).label;
  countFor = (status) => this.meta.status_counts?.[status] ?? 0;
  chipClass = (status) =>
    "paper-surveyor__chip" +
    (this.status === status ? " is-active" : "");

  scoreCell = (score) =>
    score == null ? "—" : Math.round(score * 100) + "%";
  dateCell = (iso) => (iso ? new Date(iso).toLocaleDateString() : "—");

  get statuses() {
    return STATUS_ORDER;
  }
  get routes() {
    return ROUTE_OPTIONS;
  }

  <template>
    <div class="paper-surveyor">
      <header class="paper-surveyor__header">
        <h2>{{dIcon "flask"}} Paper Surveyor</h2>
        <p class="paper-surveyor__subtitle">
          Papers seen by the OpenAlex pipeline. Filter by status or route,
          search by title / DOI / OpenAlex ID.
        </p>
      </header>

      <div class="paper-surveyor__filters">
        <div class="paper-surveyor__status-chips">
          {{#each this.statuses as |s|}}
            <button
              type="button"
              class={{this.chipClass s}}
              {{on "click" (fn this.setStatus s)}}
            >
              {{dIcon (this.iconFor s)}}
              <span class="paper-surveyor__chip-label">
                {{this.labelFor s}}
              </span>
              <span class="paper-surveyor__chip-count">
                {{this.countFor s}}
              </span>
            </button>
          {{/each}}
        </div>

        <div class="paper-surveyor__controls">
          <label class="paper-surveyor__route-label">
            {{dIcon "route"}}
            <select
              class="paper-surveyor__route-select"
              {{on "change" this.setRoute}}
            >
              {{#each this.routes as |r|}}
                <option value={{r}} selected={{eq this.route r}}>{{r}}</option>
              {{/each}}
            </select>
          </label>

          <label class="paper-surveyor__search">
            {{dIcon "magnifying-glass"}}
            <input
              type="text"
              placeholder="Search title / DOI / OpenAlex ID…"
              value={{this.search}}
              {{on "input" this.onSearchInput}}
            />
          </label>
        </div>
      </div>

      {{#if this.loading}}
        <div class="paper-surveyor__loading">
          {{dIcon "spinner"}} Loading…
        </div>
      {{else if (eq this.papers.length 0)}}
        <div class="paper-surveyor__empty">
          {{dIcon "inbox"}} No papers match these filters.
        </div>
      {{else}}
        <table class="paper-surveyor__table">
          <thead>
            <tr>
              <th>Status</th>
              <th>Title</th>
              <th>Route</th>
              <th>Type</th>
              <th>Score</th>
              <th>Published</th>
              <th>Seen</th>
              <th>Links</th>
            </tr>
          </thead>
          <tbody>
            {{#each this.papers as |p|}}
              <tr>
                <td title={{p.status}}>
                  {{dIcon (this.iconFor p.status)}}
                </td>
                <td class="paper-surveyor__title">
                  {{#if p.topic_url}}
                    <a href={{p.topic_url}}>{{p.title}}</a>
                  {{else}}
                    {{p.title}}
                  {{/if}}
                  {{#if p.error_message}}
                    <div class="paper-surveyor__err">{{p.error_message}}</div>
                  {{/if}}
                </td>
                <td>{{p.route}}</td>
                <td>{{p.work_type}}</td>
                <td>{{this.scoreCell p.relevance_score}}</td>
                <td>{{this.dateCell p.publication_date}}</td>
                <td>{{this.dateCell p.created_at}}</td>
                <td class="paper-surveyor__links">
                  <a
                    href="https://openalex.org/{{p.openalex_id}}"
                    target="_blank"
                    rel="noopener"
                    title="OpenAlex"
                  >
                    {{dIcon "up-right-from-square"}}
                  </a>
                  {{#if p.doi}}
                    <a
                      href="https://doi.org/{{p.doi}}"
                      target="_blank"
                      rel="noopener"
                      title="DOI"
                    >
                      {{dIcon "barcode"}}
                    </a>
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        <div class="paper-surveyor__pagination">
          <DButton
            @icon="chevron-left"
            @disabled={{eq this.page 1}}
            @action={{this.prevPage}}
          />
          <span>
            Page {{this.page}} of {{this.meta.total_pages}} ·
            {{this.meta.total}} total
          </span>
          <DButton
            @icon="chevron-right"
            @disabled={{eq this.page this.meta.total_pages}}
            @action={{this.nextPage}}
          />
        </div>
      {{/if}}
    </div>
  </template>
}
