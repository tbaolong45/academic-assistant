import { days, type Connector, type Item } from "../types.ts";

// Demo: sample data. Real version calls Moodle web services (core_enrol_get_users_courses, gradereport_user_get_grade_items, ...).
const m = (i: Omit<Item, "source">): Item => ({ source: "moodle", ...i });

export const moodle: Connector = {
  source: "moodle",
  async fetch() {
    return {
      courses: [
        { id: "cs201", code: "CS201", name: "Data Structures" },
        { id: "math210", code: "MATH210", name: "Linear Algebra" },
        { id: "bio150", code: "BIO150", name: "Intro to Biology" },
      ],
      items: [
        m({ externalId: "a1", kind: "deadline", courseId: "cs201", title: "Assignment 3: Binary trees", dueAt: days(2), occurredAt: days(-7) }),
        m({ externalId: "a2", kind: "deadline", courseId: "math210", title: "Problem set 6", dueAt: days(5), occurredAt: days(-5) }),
        m({ externalId: "a3", kind: "deadline", courseId: "bio150", title: "Lab report 4", dueAt: days(10), occurredAt: days(-3) }),
        m({ externalId: "a4", kind: "deadline", courseId: "cs201", title: "Final project proposal", dueAt: days(25), occurredAt: days(-1) }),
        m({ externalId: "g1", kind: "grade", courseId: "cs201", title: "Quiz 2", grade: { score: 8, max: 10 }, occurredAt: days(-1) }),
        m({ externalId: "g2", kind: "grade", courseId: "math210", title: "Midterm exam", grade: { score: 72, max: 100 }, occurredAt: days(-2) }),
        m({ externalId: "g3", kind: "grade", courseId: "bio150", title: "Lab report 3", grade: { score: 17, max: 20 }, occurredAt: days(-6), seenAt: days(-5) }),
        m({ externalId: "g4", kind: "grade", courseId: "cs201", title: "Quiz 1", grade: { score: 9, max: 10 }, occurredAt: days(-14), seenAt: days(-13) }),
        m({ externalId: "n1", kind: "announcement", courseId: "math210", title: "Lecture moved to room B204 this Thursday", from: "Dr. Nguyen", occurredAt: days(-1) }),
        m({ externalId: "n2", kind: "announcement", courseId: "bio150", title: "Midterm covers chapters 1–6", from: "Prof. Tran", occurredAt: days(-3) }),
        m({ externalId: "f1", kind: "file", courseId: "cs201", title: "Lecture 7 – AVL trees.pdf", occurredAt: days(-2) }),
        m({ externalId: "f2", kind: "file", courseId: "cs201", title: "Lecture 6 – Heaps.pdf", occurredAt: days(-9) }),
        m({ externalId: "f3", kind: "file", courseId: "math210", title: "Eigenvalues notes.pdf", occurredAt: days(-4) }),
        m({ externalId: "f4", kind: "file", courseId: "bio150", title: "Cell biology slides.pptx", occurredAt: days(-8) }),
      ],
    };
  },
};
