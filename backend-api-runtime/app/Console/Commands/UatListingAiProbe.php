<?php

namespace App\Console\Commands;

use App\Services\GeminiClient;
use App\Services\ListingAiService;
use App\Services\ListingDraftService;
use Illuminate\Console\Command;
use Illuminate\Validation\ValidationException;

/** Fixed synthetic extraction probe; no accounts, listings or provider text are exported. */
class UatListingAiProbe extends Command
{
    protected $signature = 'uat:listing-ai-check';
    protected $description = 'Diagnose one synthetic listing extraction without an Android build';

    public function handle(): int
    {
        if (! app()->environment('uat', 'staging')) {
            $this->line('AQER_LISTING_AI_PROBE {"status":"environment_refused"}');
            return self::FAILURE;
        }
        $client = new class extends GeminiClient {
            public array $validationFields = [];
            public string $shape = 'not_received';

            public function object(string $instruction, array $input, array $schema, ?array $audio = null): array
            {
                $result = parent::object($instruction, $input, $schema, $audio);
                $this->shape = isset($result['fields']) && is_array($result['fields'])
                    ? 'fields_array' : 'fields_missing_or_invalid';
                if ($this->shape === 'fields_array') {
                    $listing = new ListingAiService($this);
                    try {
                        $listing->facts($result['fields']);
                    } catch (ValidationException $error) {
                        $allowed = array_keys($listing->rules());
                        foreach (array_keys($error->errors()) as $name) {
                            $name = preg_replace('/^facts\./', '', $name);
                            $this->validationFields[] = in_array($name, $allowed, true) ? $name : 'other_schema';
                        }
                        $this->validationFields = array_values(array_unique($this->validationFields));
                        sort($this->validationFields);
                    }
                }
                return $result;
            }
        };
        $started = microtime(true);
        $status = 'unavailable';
        $matched = false;
        $proposalSource = 'not_received';
        $mismatched = [];
        $missingProposals = [];
        $current = ['type'=>'apartment', 'purpose'=>'rent', 'governorate'=>'صنعاء',
            'floor_number'=>'2', 'bedrooms'=>3, 'bathrooms'=>2,
            'has_parking'=>false, 'building_facade'=>'north'];
        try {
            $result = (new ListingDraftService(new ListingAiService($client)))->prepare(
                'شقة للإيجار في صنعاء في الدور الثاني، رقم الشقة 7، ثلاث غرف نوم وحمامان، دون موقف سيارة، واجهة شمالية.',
                $current,
            );
            $fields = (array) ($result['fields'] ?? []);
            $proposalSource = in_array($result['source'] ?? '', ['ai', 'text'], true)
                ? $result['source'] : 'other';
            $effective = array_replace($current, $fields);
            foreach (['floor_number'=>'2', 'unit_number'=>'7', 'bedrooms'=>3,
                'bathrooms'=>2, 'has_parking'=>false, 'building_facade'=>'north'] as $key=>$expected) {
                if (!array_key_exists($key, $effective) || $effective[$key] !== $expected) $mismatched[] = $key;
            }
            foreach (['floor_number', 'unit_number'] as $key) {
                if (!array_key_exists($key, $fields)) $missingProposals[] = $key;
            }
            $matched = $proposalSource === 'ai' && $mismatched === [] && $missingProposals === [];
            $status = $proposalSource !== 'ai' ? 'unavailable'
                : ($matched ? 'passed' : 'required_facts_mismatch');
        } catch (\Throwable) {
            // The provider message, response, brief and facts are never printed.
        }
        $reason = $client->probeFailure();
        if (! preg_match('/^(?:not_attempted|configuration|daily_budget|network_or_timeout|invalid_json_output|none|provider_http_[1-5][0-9]{2})$/D', $reason)) {
            $reason = 'other';
        }
        $this->line('AQER_LISTING_AI_PROBE '.json_encode([
            'status'=>$status, 'provider_stage'=>$reason, 'response_shape'=>$client->shape,
            'invalid_field_names'=>$client->validationFields, 'required_facts_match'=>$matched,
            'proposal_source'=>$proposalSource, 'mismatched_required_fields'=>$mismatched,
            'missing_required_proposals'=>$missingProposals,
            'elapsed_ms'=>(int) round((microtime(true)-$started)*1000),
            'listing_writes'=>false, 'native_acceptance'=>false,
        ], JSON_UNESCAPED_SLASHES));
        return $matched ? self::SUCCESS : self::FAILURE;
    }
}
