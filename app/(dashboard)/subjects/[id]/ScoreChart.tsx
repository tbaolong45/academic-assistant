"use client";

import { useRef, useState } from "react";
import { band, bandLabels, runningGrade, stillToCome, type Assessment, type Subject } from "../../../../lib/dashboard.ts";
import s from "./ScoreChart.module.css";

const ticks = [0, 25, 50, 75, 100];
const shade = (weight: number) => `var(--s${band(weight)})`;
const fmtDate = (iso: string) =>
  new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" }).replace(",", "");

export function ScoreChart({ subject }: { subject: Subject }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [sel, setSel] = useState<Assessment | null>(null);
  const grade = runningGrade(subject);
  const toCome = stillToCome(subject);
  const soFar = subject.assessments.reduce((t, x) => t + x.weight, 0) - toCome;

  const open = (a: Assessment) => {
    setSel(a);
    dialog.current?.showModal();
  };

  return (
    <section className={s.root}>
      <p className={s.kicker}>Running grade</p>
      <p className={s.hero}>{grade === null ? "—" : `${grade.toFixed(1)}%`}</p>
      <p className={s.sub}>
        from {soFar}% of the grade so far · {toCome}% still to come
      </p>

      <div className={s.chart}>
        <div className={s.yAxis} aria-hidden>
          {ticks.map((t) => (
            <span key={t} style={{ bottom: `${t}%` }}>{t}%</span>
          ))}
        </div>
        <div className={s.grid} aria-hidden>
          {ticks.map((t) => (
            <i key={t} style={{ bottom: `${t}%` }} />
          ))}
        </div>
        <div className={s.scroller}>
          <div className={s.cols}>
            {subject.assessments.map((a) => {
              const up = a.score === undefined;
              return (
                <button
                  key={a.id}
                  type="button"
                  className={s.col}
                  onClick={() => open(a)}
                  aria-label={`${a.name}: ${up ? "upcoming" : `scored ${a.score}%`}, ${a.weight}% of course grade`}
                >
                  <span className={s.track}>
                    {up ? (
                      <span className={`${s.bar} ${s.upcoming}`} style={{ borderColor: shade(a.weight) }}>
                        <span>upcoming</span>
                      </span>
                    ) : (
                      <>
                        <span className={s.value} style={{ bottom: `${a.score}%` }}>{a.score}%</span>
                        <span className={s.bar} style={{ height: `${a.score}%`, background: shade(a.weight) }} />
                      </>
                    )}
                  </span>
                  <span className={s.name}>{a.name}</span>
                  <span className={s.weight}>{a.weight}%</span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <ul className={s.legend}>
        <li className={s.legendTitle}>Shade = share of course grade</li>
        {bandLabels.map((label, i) => (
          <li key={label}>
            <i className={s.swatch} style={{ background: `var(--s${i})` }} />
            {label}
          </li>
        ))}
        <li>
          <i className={`${s.swatch} ${s.outline}`} />
          Upcoming
        </li>
      </ul>

      <details className={s.table}>
        <summary>Show as table</summary>
        <table>
          <thead>
            <tr><th>Name</th><th>Date</th><th>Score</th><th>Weight</th><th>Status</th></tr>
          </thead>
          <tbody>
            {subject.assessments.map((a) => (
              <tr key={a.id}>
                <td>{a.name}</td>
                {/* Local-timezone date can differ between server and browser near midnight. */}
                <td suppressHydrationWarning>{fmtDate(a.date)}</td>
                <td>{a.score === undefined ? "—" : `${a.score}%`}</td>
                <td>{a.weight}%</td>
                <td>{a.score === undefined ? "Upcoming" : "Graded"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>

      <dialog
        ref={dialog}
        className={s.sheet}
        aria-labelledby="score-sheet-title"
        onClick={(e) => e.target === e.currentTarget && dialog.current?.close()}
      >
        {sel && (
          <div className={s.sheetBody}>
            <div className={s.sheetHead}>
              <h2 id="score-sheet-title">{sel.name}</h2>
              <button type="button" className={s.close} onClick={() => dialog.current?.close()}>
                Close
              </button>
            </div>
            {sel.score === undefined && <p className={s.status}>Upcoming, not graded yet</p>}
            <dl className={s.facts}>
              <dt>Type</dt>
              <dd>{sel.type}</dd>
              <dt>Date</dt>
              <dd>{fmtDate(sel.date)}</dd>
              <dt>Raw score</dt>
              <dd>{sel.raw ? `${sel.raw.got} / ${sel.raw.max}` : "—"}</dd>
              <dt>Score</dt>
              <dd>{sel.score === undefined ? "—" : `${sel.score}%`}</dd>
              <dt>Weight</dt>
              <dd>
                <i className={s.swatch} style={{ background: shade(sel.weight) }} />
                {sel.weight}% of course grade <span className={s.muted}>({bandLabels[band(sel.weight)]} band)</span>
              </dd>
            </dl>
            <h3 className={s.topicsTitle}>Topics covered</h3>
            <ul className={s.chips}>
              {sel.topics.map((t) => <li key={t}>{t}</li>)}
            </ul>
          </div>
        )}
      </dialog>
    </section>
  );
}
