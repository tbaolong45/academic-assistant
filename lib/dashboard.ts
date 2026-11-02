import { days } from "./types.ts";

// ponytail: sample data for the Course Dashboard demo; real data will come from the connectors in lib/store.ts.

export type Hue = "blue" | "green" | "orange";
export type AssessmentType = "Quiz" | "Assignment" | "Midterm" | "Final" | "Lab" | "Project" | "Mini-exam";

export type Assessment = {
  id: string;
  name: string;
  type: AssessmentType;
  date: string; // ISO-8601
  weight: number; // % of the course grade
  score?: number; // %; undefined = upcoming
  raw?: { got: number; max: number };
  topics: string[];
};

export type Subject = {
  id: string;
  name: string;
  code: string;
  hue: Hue;
  assessments: Assessment[]; // ordered by date
  assignments: { title: string; due: string; status: "Submitted" | "Open" }[];
  materials: { title: string; kind: "Slides" | "Recording" | "Notes" | "Reading"; date: string }[];
  announcements: { title: string; source: "Moodle" | "Outlook" | "Teams"; from: string; date: string }[];
};

const a = (id: string, name: string, type: AssessmentType, d: number, weight: number, topics: string[], raw?: [number, number]): Assessment => ({
  id, name, type, date: days(d), weight, topics,
  ...(raw && { raw: { got: raw[0], max: raw[1] }, score: Math.round((raw[0] / raw[1]) * 100) }),
});

export const subjects: Subject[] = [
  {
    id: "linear-algebra", name: "Linear Algebra", code: "MATH210", hue: "blue",
    assessments: [
      a("q1", "Quiz 1", "Quiz", -49, 4, ["Vectors", "Linear combinations"], [17, 20]),
      a("q2", "Quiz 2", "Quiz", -35, 4, ["Matrix operations", "Inverses"], [18, 25]),
      a("a1", "Assignment 1", "Assignment", -28, 10, ["Systems of equations", "Gaussian elimination"], [45, 50]),
      a("mid", "Midterm", "Midterm", -10, 30, ["Vector spaces", "Determinants", "Rank"], [78, 100]),
      a("a2", "Assignment 2", "Assignment", 2, 12, ["Eigenvalues", "Diagonalisation"]),
      a("final", "Final", "Final", 48, 40, ["All topics", "Emphasis on eigen-decomposition and orthogonality"]),
    ],
    assignments: [
      { title: "Assignment 2: Eigenvalues", due: days(2), status: "Open" },
      { title: "Assignment 1: Gaussian elimination", due: days(-28), status: "Submitted" },
    ],
    materials: [
      { title: "Lecture 9: Eigenvalues.pdf", kind: "Slides", date: days(-2) },
      { title: "Lecture 9 recording", kind: "Recording", date: days(-2) },
      { title: "Determinants worked examples", kind: "Notes", date: days(-12) },
    ],
    announcements: [
      { title: "Thursday lecture moved to room B204", source: "Moodle", from: "Dr. Nguyen", date: days(-1) },
      { title: "Midterm results and solutions posted", source: "Outlook", from: "Dr. Nguyen", date: days(-4) },
      { title: "Extra office hour before Assignment 2", source: "Teams", from: "TA Linh", date: days(-5) },
    ],
  },
  {
    id: "intro-to-ai", name: "Intro to AI", code: "CS240", hue: "green",
    assessments: [
      a("q1", "Quiz 1", "Quiz", -45, 5, ["Intelligent agents", "Search problems"], [23, 25]),
      a("me1", "Mini-exam 1", "Mini-exam", -30, 15, ["Uninformed search", "A* and heuristics"], [81, 100]),
      a("proj", "Project", "Project", -12, 20, ["Constraint satisfaction", "Game playing"], [44, 50]),
      a("mid", "Midterm", "Midterm", 4, 25, ["Probability", "Bayesian networks"]),
      a("final", "Final", "Final", 50, 35, ["All topics", "Emphasis on learning and planning"]),
    ],
    assignments: [
      { title: "Project report: Connect-4 agent", due: days(-12), status: "Submitted" },
      { title: "Problem set 4: Bayes nets", due: days(9), status: "Open" },
    ],
    materials: [
      { title: "Week 8: Bayesian networks.pdf", kind: "Slides", date: days(-3) },
      { title: "Russell & Norvig ch. 13", kind: "Reading", date: days(-3) },
    ],
    announcements: [
      { title: "Midterm covers weeks 5–8 only", source: "Moodle", from: "Prof. Tran", date: days(-2) },
      { title: "Project grades released", source: "Teams", from: "Prof. Tran", date: days(-6) },
    ],
  },
  {
    id: "advanced-python", name: "Advanced Python", code: "CS310", hue: "orange",
    assessments: [
      a("lab1", "Lab 1", "Lab", -40, 3, ["Virtual environments", "Packaging"], [10, 10]),
      a("q1", "Quiz 1", "Quiz", -33, 5, ["Iterators", "Generators"], [14, 20]),
      a("me", "Mini-exam", "Mini-exam", -18, 15, ["Decorators", "Context managers"], [42, 50]),
      a("a2", "Assignment 2", "Assignment", 6, 12, ["asyncio", "Async I/O"]),
      a("mid", "Midterm", "Midterm", 20, 25, ["Typing", "Concurrency", "Metaclasses"]),
      a("final", "Final", "Final", 52, 40, ["All topics"]),
    ],
    assignments: [
      { title: "Assignment 2: async web scraper", due: days(6), status: "Open" },
      { title: "Assignment 1: CLI with decorators", due: days(-21), status: "Submitted" },
      { title: "Lab 2: profiling", due: days(11), status: "Open" },
    ],
    materials: [
      { title: "Lecture 7: asyncio.pdf", kind: "Slides", date: days(-1) },
      { title: "Lecture 7 recording", kind: "Recording", date: days(-1) },
      { title: "Fluent Python ch. 21", kind: "Reading", date: days(-6) },
    ],
    announcements: [
      { title: "Assignment 2 starter code updated", source: "Moodle", from: "Dr. Le", date: days(-1) },
      { title: "Lab room change this week", source: "Outlook", from: "CS Department", date: days(-3) },
    ],
  },
];

export const getSubject = (id: string) => subjects.find((s) => s.id === id);

const done = (s: Subject) => s.assessments.filter((x) => x.score !== undefined);

/** Weighted average of completed assessments only, 1 decimal; null if nothing graded yet. */
export function runningGrade(s: Subject) {
  const d = done(s);
  const w = d.reduce((t, x) => t + x.weight, 0);
  return w ? Math.round((d.reduce((t, x) => t + x.weight * x.score!, 0) / w) * 10) / 10 : null;
}

/** % of the course grade not yet assessed. */
export const stillToCome = (s: Subject) => s.assessments.filter((x) => x.score === undefined).reduce((t, x) => t + x.weight, 0);

/** Shade band by weight: 0 = <5%, 1 = 5–15%, 2 = 15–30%, 3 = >30%. Higher = darker. */
export const band = (weight: number) => (weight < 5 ? 0 : weight <= 15 ? 1 : weight <= 30 ? 2 : 3);
export const bandLabels = ["<5%", "5–15%", "15–30%", ">30%"];

/** Next upcoming deadlines/exams across all subjects, soonest first. */
export const thisWeek = (n = 3, now = Date.now()) =>
  subjects
    .flatMap((subject) => subject.assessments.filter((x) => x.score === undefined && Date.parse(x.date) >= now).map((assessment) => ({ subject, assessment })))
    .sort((p, q) => Date.parse(p.assessment.date) - Date.parse(q.assessment.date))
    .slice(0, n);
