# --- Bedrock Guardrail for Enterprise RAG Governance ---
resource "aws_bedrock_guardrail" "rag" {
  name                      = "${var.project_name}-${var.environment}-guardrail"
  description               = "Production Bedrock Guardrail with prompt injection defense, PII masking, and topic filtering"
  blocked_input_messaging   = "I am unable to process this request because it violated the enterprise safety and security policy."
  blocked_outputs_messaging = "The generated response was withheld in accordance with enterprise data protection and compliance guidelines."
  kms_key_arn               = var.kms_key_arn

  # 1. Content Policy Config: Defense against prompt injection, jailbreaks, and harmful content
  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }

    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }

  # 2. Sensitive Information Policy Config: PII Redaction / Masking / Blocking
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "US_BANK_ACCOUNT_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "BLOCK"
    }
  }

  # 3. Topic Policy Config: Denied Out-of-Scope Enterprise Topics
  topic_policy_config {
    topics_config {
      name       = "MaliciousCyberExploitation"
      definition = "Requests providing active vulnerability exploit code, malware authoring, or unauthorized penetration instructions."
      examples = [
        "Write a buffer overflow exploit for CVE-2024-1234",
        "Generate a reverse shell payload to bypass firewalls"
      ]
      type = "DENY"
    }

    topics_config {
      name       = "UnauthorizedLegalAdvice"
      definition = "Requests asking the model to provide authoritative legal contracts, formal legal counsel, or binding legal opinions."
      examples = [
        "Provide binding legal advice for my lawsuit",
        "Draft a legally certified power of attorney"
      ]
      type = "DENY"
    }
  }

  # 4. Contextual Grounding Policy: Hallucination and Relevance Defense
  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = 0.70
    }
    filters_config {
      type      = "RELEVANCE"
      threshold = 0.70
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-guardrail"
  }
}

# --- Guardrail Version for Production Release Stability ---
resource "aws_bedrock_guardrail_version" "prod" {
  guardrail_arn = aws_bedrock_guardrail.rag.guardrail_arn
  description   = "Production Version 1.0"
}
