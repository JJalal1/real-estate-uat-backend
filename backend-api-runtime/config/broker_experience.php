<?php

return [
    // Historical records and financial settlements remain readable. New broker journeys record outcomes only.
    'legacy_contract_creation' => (bool) env('LEGACY_CONTRACT_CREATION_ENABLED', false),
];
