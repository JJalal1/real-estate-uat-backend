<?php
namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

/** All application geocoding shares this fleet-wide budget, including manager search. */
class GeocodingGateway
{
    public const ATTRIBUTION='© OpenStreetMap contributors · ODbL · Nominatim / Photon';

    public function get(string $provider, string $path, array $query): array
    {
        if (!in_array($provider,['nominatim','photon'],true) || !config('geocoding.enabled')) return ['status'=>'disabled','data'=>[]];
        $base=rtrim((string)config('geocoding.'.$provider.'_url'),'/');
        $parts=parse_url($base);
        if (!$parts || ($parts['scheme'] ?? '')!=='https' || empty($parts['host']) || isset($parts['user']) || isset($parts['pass'])) return ['status'=>'disabled','data'=>[]];
        $host=strtolower($parts['host']);
        // Manager place search is an autocomplete flow. The public Nominatim
        // service forbids that use, even below its numerical request limit.
        if ($provider==='nominatim' && $host==='nominatim.openstreetmap.org' && $path==='/search') return ['status'=>'public_autocomplete_disabled','data'=>[]];
        if (in_array($host,['nominatim.openstreetmap.org','photon.komoot.io'],true)) {
            // Public providers receive a roughly 100m area centre, never the
            // precise private home pin. Distances use the original pin locally.
            foreach (['lat','lon'] as $coordinate) if (is_numeric($query[$coordinate] ?? null)) $query[$coordinate]=round((float)$query[$coordinate],3);
        }
        try {
            $store=(string)config('geocoding.cache_store','database');
            // Fail closed when a shared atomic limiter is not configured.
            if (!in_array(config('cache.stores.'.$store.'.driver'),['database','redis','memcached'],true) && !app()->environment('testing')) return ['status'=>'shared_cache_required','data'=>[]];
            $cache=Cache::store($store);
            $key='geocoding:v2:'.hash('sha256',json_encode([$provider,$base,$path,$query]));
            $cached=$cache->get($key);
            if (is_array($cached)) return $cached+['cached'=>true];
            // Atomic insert, shared by every endpoint and instance. Two seconds
            // deliberately stay below the public service's 1 request/sec ceiling.
            if (!$cache->add('geocoding:v2:global:'.$provider,true,2)) return ['status'=>'rate_limited','data'=>[]];
            $response=Http::acceptJson()->withHeaders(['User-Agent'=>(string)config('geocoding.user_agent'),'Accept-Language'=>'ar'])
                ->withOptions(['allow_redirects'=>false])->connectTimeout(1)->timeout(2)->get($base.$path,$query);
            $data=$response->successful() && strlen($response->body())<=200000 ? $response->json() : null;
            $result=['status'=>is_array($data)?'ok':($response->successful()?'invalid_response':'http_'.$response->status()),'data'=>is_array($data)?$data:[]];
            $cache->put($key,$result,$result['status']==='ok'?43200:20);
            return $result;
        } catch (\Throwable) {
            // Never log the request URL, coordinates, body or provider exception.
            return ['status'=>'unavailable','data'=>[]];
        }
    }
}
