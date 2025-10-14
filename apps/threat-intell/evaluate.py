#!/usr/bin/env python3
"""
Compute extraction quality metrics for the threat intelligence pipeline.

This script only depends on psycopg/psycopg2 and can be executed from a
laptop or from an automation job. Provide connection details via the usual
Postgres environment variables (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)
or a full DATABASE_URL.
"""
from __future__ import annotations

import argparse
import collections
import contextlib
import json
import os
import statistics
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Tuple


@contextlib.contextmanager
def connect():
    """Yield a psycopg connection using environment configuration."""
    dsn = os.environ.get("DATABASE_URL")
    try:  # Prefer modern psycopg (v3)
        import psycopg

        conn = psycopg.connect(dsn or "", autocommit=False)
    except ModuleNotFoundError:
        import psycopg2  # type: ignore

        conn = psycopg2.connect(dsn or "")
    try:
        yield conn
    finally:
        conn.close()


@dataclass
class Metrics:
    extractor: str
    tp: int = 0
    fp: int = 0
    fn: int = 0

    @property
    def precision(self) -> float:
        return self.tp / (self.tp + self.fp) if (self.tp + self.fp) else 0.0

    @property
    def recall(self) -> float:
        return self.tp / (self.tp + self.fn) if (self.tp + self.fn) else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return (2 * p * r) / (p + r) if (p + r) else 0.0


def fetch_labeled_examples(cursor) -> Iterable[Tuple[str, str, str]]:
    """
    Return (extractor, label, ioc_type) triples for human labeled indicators.
    label is one of TP, FP, UNKNOWN.
    """
    cursor.execute(
        """
        SELECT i.extractor, l.label, i.ioc_type
        FROM threatintel.labels l
        JOIN threatintel.ioc i ON i.id = l.ioc_id
        WHERE l.labeled_at > NOW() - INTERVAL '90 days';
        """
    )
    return cursor.fetchall()


def fetch_latency(cursor) -> List[float]:
    """Return minutes between doc collection and IOC validation."""
    cursor.execute(
        """
        SELECT EXTRACT(EPOCH FROM (fc.updated_at - rd.collected_at)) / 60.0 AS minutes
        FROM threatintel.final_candidate fc
        JOIN threatintel.ioc i ON i.id = fc.ioc_id
        JOIN threatintel.raw_doc rd ON rd.id = i.doc_id
        WHERE fc.status = 'validated'
          AND fc.updated_at > NOW() - INTERVAL '30 days';
        """
    )
    return [row[0] for row in cursor.fetchall()]


def compute_metrics(rows: Iterable[Tuple[str, str, str]]) -> Dict[str, Metrics]:
    """Aggregate labeled data into precision/recall metrics."""
    metrics: Dict[str, Metrics] = {}
    for extractor, label, _ioc_type in rows:
        metrics.setdefault(extractor, Metrics(extractor))
        m = metrics[extractor]
        if label.upper() == "TP":
            m.tp += 1
        elif label.upper() == "FP":
            m.fp += 1
        elif label.upper() == "FN":
            m.fn += 1
    return metrics


def print_report(metrics: Dict[str, Metrics], latency_minutes: List[float]) -> None:
    """Pretty-print metrics in a compact table."""
    print("\n=== Extraction Quality ===")
    header = f"{'Extractor':<12} {'TP':>5} {'FP':>5} {'FN':>5} {'Precision':>10} {'Recall':>10} {'F1':>10}"
    print(header)
    print("-" * len(header))
    for name, metric in sorted(metrics.items()):
        print(
            f"{name:<12} {metric.tp:>5} {metric.fp:>5} {metric.fn:>5} "
            f"{metric.precision:>10.3f} {metric.recall:>10.3f} {metric.f1:>10.3f}"
        )

    if latency_minutes:
        p95 = statistics.quantiles(latency_minutes, n=20)[-1]
        print("\n=== Validation Latency (minutes) ===")
        print(
            json.dumps(
                {
                  "count": len(latency_minutes),
                  "avg": round(statistics.mean(latency_minutes), 2),
                  "p95": round(p95, 2),
                  "max": round(max(latency_minutes), 2),
                },
                indent=2,
            )
        )


def export_json(metrics: Dict[str, Metrics], latency_minutes: List[float], path: str) -> None:
    """Write metrics to JSON for downstream consumption."""
    payload = {
        "extractors": {
            name: {
                "tp": metric.tp,
                "fp": metric.fp,
                "fn": metric.fn,
                "precision": metric.precision,
                "recall": metric.recall,
                "f1": metric.f1,
            }
            for name, metric in metrics.items()
        },
        "latency_minutes": latency_minutes,
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
    print(f"\nWrote results to {path}")


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate threat intelligence extraction performance."
    )
    parser.add_argument(
        "--json",
        dest="json_path",
        help="Optional path to write metrics as JSON.",
    )
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    args = parse_args(argv)
    with connect() as conn:
        with conn.cursor() as cursor:
            labeled_rows = list(fetch_labeled_examples(cursor))
            latency = fetch_latency(cursor)

    if not labeled_rows:
        print("No labeled examples found. Add records to threatintel.labels and retry.")
        return 1

    metrics = compute_metrics(labeled_rows)
    print_report(metrics, latency)

    if args.json_path:
        export_json(metrics, latency, args.json_path)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
