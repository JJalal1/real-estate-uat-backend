<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use League\Flysystem\CorruptedPathDetected;
use League\Flysystem\WhitespacePathNormalizer;
use Symfony\Component\HttpFoundation\HeaderUtils;
use Tests\TestCase;

class SecurityDependencyRegressionTest extends TestCase
{
    use RefreshDatabase;

    public function test_cache_control_with_long_whitespace_retains_its_directives(): void
    {
        // The old backtracking pattern could exhaust PCRE and silently drop
        // the complete header. Assert semantics instead of a flaky CPU timer.
        $header = 'public'.str_repeat(' ', 64).', max-age=60';
        $this->assertSame([['public'], ['max-age', '60']], HeaderUtils::split($header, ',='));
    }

    public function test_security_fix_also_preserves_whitespace_separators(): void
    {
        // 8.1.9 includes the follow-up to the first security patch.
        // One separator produces one flat level in HeaderUtils' contract.
        $this->assertSame(['foo', 'bar'], HeaderUtils::split('foo bar', ' '));
    }

    public function test_malformed_utf8_cannot_bypass_storage_path_validation(): void
    {
        $normalizer = new WhitespacePathNormalizer();
        $this->assertSame('مجلد/صورة.jpg', $normalizer->normalizePath('مجلد/./صورة.jpg'));
        $this->expectException(CorruptedPathDetected::class);
        $normalizer->normalizePath("editor-drafts/1/\xc3(\x00.jpg");
    }

    public function test_non_string_query_credentials_never_authenticate_the_application_api(): void
    {
        // This application uses a hashed bearer middleware and PostgreSQL,
        // rather than the built-in TokenGuard/MySQL combination in the advisory.
        // Still reject the malformed credential through the actual API route.
        $this->getJson('/api/auth/me?api_token[user_id]=1')->assertUnauthorized();
        $this->withToken('synthetic-invalid-token')->getJson('/api/auth/me')->assertUnauthorized();
    }
}
