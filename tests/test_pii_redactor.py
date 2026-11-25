"""Unit tests for PII Redaction module."""

import unittest
from unittest.mock import MagicMock
from src.ingestion.pii_redactor import PIIRedactor


class TestPIIRedactor(unittest.TestCase):

    def setUp(self):
        # Mock comprehend client so unit tests run completely offline
        self.mock_comprehend = MagicMock()
        self.mock_comprehend.detect_pii_entities.return_value = {"Entities": []}
        self.redactor = PIIRedactor(comprehend_client=self.mock_comprehend)

    def test_redact_ssn(self):
        text = "The employee's SSN is 123-45-6789 and needs protection."
        redacted, entities = self.redactor.redact_pii(text)
        self.assertIn("SSN", entities)
        self.assertNotIn("123-45-6789", redacted)
        self.assertIn("[REDACTED_SSN]", redacted)

    def test_redact_credit_card(self):
        text = "Billing card number: 4532-1234-5678-9012 on file."
        redacted, entities = self.redactor.redact_pii(text)
        self.assertIn("CREDIT_CARD", entities)
        self.assertNotIn("4532-1234-5678-9012", redacted)
        self.assertIn("[REDACTED_CREDIT_CARD]", redacted)

    def test_redact_email_and_phone(self):
        text = "Contact john.doe@enterprise.corp or call 555-123-4567 for inquiries."
        redacted, entities = self.redactor.redact_pii(text)
        self.assertIn("EMAIL", entities)
        self.assertIn("PHONE", entities)
        self.assertNotIn("john.doe@enterprise.corp", redacted)
        self.assertNotIn("555-123-4567", redacted)

    def test_redact_aws_key(self):
        text = "Leaked key: AKIAIOSFODNN7EXAMPLE in debug log."
        redacted, entities = self.redactor.redact_pii(text)
        self.assertIn("AWS_KEY", entities)
        self.assertNotIn("AKIAIOSFODNN7EXAMPLE", redacted)
        self.assertIn("[REDACTED_AWS_KEY]", redacted)

    def test_comprehend_entity_redaction(self):
        text = "Meeting with Alice Smith in Seattle."
        self.mock_comprehend.detect_pii_entities.return_value = {
            "Entities": [
                {
                    "Type": "NAME",
                    "Score": 0.99,
                    "BeginOffset": 13,
                    "EndOffset": 24,
                }
            ]
        }
        redacted, entities = self.redactor.redact_pii(text)
        self.assertIn("NAME", entities)
        self.assertNotIn("Alice Smith", redacted)
        self.assertIn("[REDACTED_NAME]", redacted)


if __name__ == "__main__":
    unittest.main()
