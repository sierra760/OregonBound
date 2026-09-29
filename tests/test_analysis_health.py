import unittest
from scripts.analysis_health import daily_health, original_tables, signed_div


class OriginalHealthAnalysisTests(unittest.TestCase):
    def test_signed_auxiliary_decay_truncates_toward_zero(self):
        self.assertEqual(signed_div(-1, 2), 0)
        self.assertEqual(daily_health()['auxiliary'], 0)
        self.assertEqual(daily_health(auxiliary=5)['auxiliary'], 2)

    def test_last_food_day_is_not_a_starvation_day(self):
        result = daily_health(food=1)
        self.assertEqual(result['badness'], 2)
        self.assertEqual(result['food'], 0)
        self.assertEqual(daily_health(food=0)['badness'], 19)

    def test_rest_suppresses_pace_but_keeps_weather_and_nutrition(self):
        result = daily_health(badness=50, flags=4, weather=5, rations=2)
        self.assertEqual(result['badness'], 51)  # 45 retained +2 snow +4 bare bones
        self.assertEqual(result['food'], 95)
        self.assertEqual(daily_health(badness=50, flags=8, weather=5, rations=2), result)

    def test_recovering_illness_still_contributes_on_last_day(self):
        result = daily_health(members=[(255, 0), (4, 1), (9, 0), (2, 0)])
        self.assertEqual(result['terms']['illnesses'], 2)
        self.assertEqual(result['members'], [(255, 0), (255, 0), (9, 0), (2, 255)])
        self.assertEqual(result['recovered'], [1])

    def test_threshold_uses_stored_byte_not_unbounded_sum(self):
        result = daily_health(badness=139, pending=20)
        self.assertEqual(result['stored_before_threshold'], 147)
        self.assertTrue(result['threshold_exceeded'])
        self.assertEqual(result['badness'], 139)
        wrapped = daily_health(pending=255)
        self.assertEqual(wrapped['badness'], 1)  # 2 +255 wraps before comparison
        self.assertFalse(wrapped['threshold_exceeded'])
        self.assertEqual(wrapped['pending'], 0)

    def test_clothing_divides_by_survivors_before_penalty(self):
        result = daily_health(temperature=0, clothing=14, survivors=5)
        self.assertEqual(result['terms']['clothing'], 3)
        self.assertEqual(result['badness'], 8)  # cold2 +clothing3 +pace2 +aux1

    def test_initialized_climate_tables_match_instruction_addressing(self):
        tables = original_tables()
        self.assertEqual(tables['temperature_base'][0], [19, 23, 33, 46, 55, 65, 70, 68, 60, 49, 35, 24])
        self.assertEqual(tables['temperature_base'][5][-1], 31)
        self.assertEqual(tables['precipitation_threshold'][0][:4], [39, 42, 78, 99])
        self.assertEqual(tables['precipitation_threshold'][5][-1], 192)


if __name__ == '__main__':
    unittest.main()
