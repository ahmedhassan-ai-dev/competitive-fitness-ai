import csv
import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_lab import evaluate, match_events, read_manifest


class TestPoseLab(unittest.TestCase):
    def test_event_matching_one_to_one(self):
        self.assertEqual(match_events([100, 140, 900], [120, 920], 70), (2, 1, 0))
        self.assertEqual(match_events([100, 140], [120, 920], 70), (1, 1, 1))

    def test_fixture_manifest_has_two_exercises(self):
        path = Path(__file__).resolve().parents[1] / 'fixtures/sessions.csv'
        sessions = read_manifest(path)
        self.assertEqual({r['exercise'] for r in sessions}, {'pushup', 'squat'})

    def test_read_manifest_refuses_missing_truth(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp)/'manifest.csv'
            file.write_text('session_id,exercise,pose_jsonl,ground_truth_reps\nabc,squat,data.jsonl,\n')
            with self.assertRaises(ValueError):
                read_manifest(file)

    def test_summary_never_fakes_precision_without_events(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root/'sessions.csv'
            manifest.write_text('session_id,exercise,pose_jsonl,ground_truth_reps\n'
                                'abc,pushup,sample.jsonl,3\n')
            predictions = root/'predictions'
            predictions.mkdir()
            (predictions/'abc.json').write_text(json.dumps({
                'predicted_reps': 2, 'rep_timestamps_ms': [500, 1000], 'frames': 40
            }))
            data = evaluate(read_manifest(manifest), manifest, predictions, 550)
            self.assertEqual(data[0]['absolute_error'], 1)
            self.assertEqual(data[0]['precision'], '')
            self.assertEqual(data[0]['recall'], '')

    def test_evaluate_with_annotated_events(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'times.json').write_text(json.dumps([500, 1000]))
            manifest = root/'sessions.csv'
            manifest.write_text('session_id,exercise,pose_jsonl,ground_truth_reps,truth_events_json\n'
                                'abc,pushup,sample.jsonl,2,times.json\n')
            predictions = root/'predictions'
            predictions.mkdir()
            (predictions/'abc.json').write_text(json.dumps({
                'predicted_reps': 3, 'rep_timestamps_ms': [510, 1005, 1700], 'frames': 30
            }))
            data = evaluate(read_manifest(manifest), manifest, predictions, 550)
            self.assertEqual((data[0]['tp'],data[0]['fp'],data[0]['fn']), (2,1,0))
            self.assertEqual(data[0]['precision'], 0.6667)
            self.assertEqual(data[0]['recall'], 1.0)


if __name__ == '__main__':
    unittest.main()
