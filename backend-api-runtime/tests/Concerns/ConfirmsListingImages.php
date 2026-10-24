<?php

namespace Tests\Concerns;

/**
 * Confirm listing image relevance using the same authenticated staff API as
 * the mobile review workspace; never mutate review rows in test fixtures.
 */
trait ConfirmsListingImages
{
    protected function confirmListingImages(int $listingId, array $reviewerHeaders): void
    {
        $url = "/api/admin/listing-review/listings/$listingId";
        $detail = $this->withHeaders($reviewerHeaders)->getJson($url)->assertOk();
        $images = $detail->json('data.images');
        $this->assertIsArray($images);
        $this->assertNotEmpty($images, 'A listing cannot be published without pictures.');

        foreach ($images as $image) {
            $token = (string) ($image['relevance_token'] ?? '');
            $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/D', $token);
            $this->withHeaders($reviewerHeaders)->postJson("$url/media-review", [
                'image_id' => (int) $image['id'],
                'image_token' => $token,
                'decision' => 'relevant',
                'reason' => 'The reviewer confirmed that the photo belongs to this property.',
            ])->assertOk()->assertJsonPath('data.decision', 'relevant');
        }
    }
}
