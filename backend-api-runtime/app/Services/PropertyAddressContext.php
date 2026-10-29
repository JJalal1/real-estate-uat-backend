<?php
namespace App\Services;

/** Typed suggestions from licensed source data; never moves the caller's pin. */
class PropertyAddressContext
{
    public function __construct(private readonly GeocodingGateway $gateway) {}

    public function resolve(float $latitude,float $longitude,?string $internalGovernorate,?string $internalArea,bool $landmarks=false): array
    {
        $n=$this->gateway->get('nominatim','/reverse',['format'=>'jsonv2','lat'=>$latitude,'lon'=>$longitude,'zoom'=>18,'addressdetails'=>1,'namedetails'=>1,'accept-language'=>'ar']);
        $data=$n['data'];$address=is_array($data['address'] ?? null)?$data['address']:[];
        $values=[
            'governorate'=>$this->clean($internalGovernorate) ?? $this->first($address,['state','province']),
            'city'=>$this->first($address,['city','town','village']),
            'district'=>$this->first($address,['district','county','state_district','city_district']),
            'neighborhood'=>$this->first($address,['neighbourhood','suburb','quarter']) ?? $this->clean($internalArea),
            'street'=>$this->first($address,['road','pedestrian','residential','footway','path']),
        ];
        $sources=[];
        foreach ($values as $key=>$value) if ($value!==null) $sources[$key]=($key==='governorate' && $this->clean($internalGovernorate)!==null) || ($key==='neighborhood' && $this->first($address,['neighbourhood','suburb','quarter'])===null)?'internal':'nominatim';
        $p=['status'=>'not_needed','data'=>[]];
        if ($landmarks || $values['governorate']===null || ($values['district']===null && $values['neighborhood']===null) || $values['street']===null) {
            $query=['lat'=>$latitude,'lon'=>$longitude,'limit'=>$landmarks?8:5,'radius'=>$landmarks?1:10];
            if ($landmarks) $query['include']='osm.amenity.place_of_worship,osm.amenity.school,osm.amenity.marketplace,osm.amenity.hospital,osm.amenity.community_centre,osm.amenity.events_venue,osm.shop.supermarket';
            $p=$this->gateway->get('photon','/reverse',$query);
            foreach ($p['data']['features'] ?? [] as $feature) {
                if (!is_array($feature)) continue;
                $properties=is_array($feature['properties'] ?? null)?$feature['properties']:[];
                $candidate=['governorate'=>$this->first($properties,['state']), 'city'=>$this->first($properties,['city']),
                    'district'=>$this->first($properties,['county']), 'neighborhood'=>$this->first($properties,['district','locality']),
                    'street'=>$this->first($properties,['street']) ?? (($properties['osm_key'] ?? '')==='highway'?$this->first($properties,['name']):null)];
                foreach ($candidate as $key=>$value) if ($values[$key]===null && $value!==null) { $values[$key]=$value;$sources[$key]='photon'; }
            }
        }
        $providers=[];
        if ($n['status']==='ok') $providers[]='nominatim';
        if ($p['status']==='ok') $providers[]='photon';
        if ($internalGovernorate!==null || $internalArea!==null) $providers[]='internal';
        $nearby=[];
        if ($landmarks) {
            foreach ($p['data']['features'] ?? [] as $feature) {
                if (!is_array($feature)) continue;
                $candidate=$this->landmark($feature,$latitude,$longitude);
                if ($candidate!==null) $nearby[$candidate['source_url']]=$candidate;
            }
            // A reverse result can itself be a real named landmark.
            $candidate=$this->landmark(['properties'=>['name'=>$data['name'] ?? null,'osm_key'=>$data['category'] ?? $data['class'] ?? null,
                'osm_value'=>$data['type'] ?? null,'osm_id'=>$data['osm_id'] ?? null,'osm_type'=>$data['osm_type'] ?? null],
                'geometry'=>['type'=>'Point','coordinates'=>[$data['lon'] ?? null,$data['lat'] ?? null]]],$latitude,$longitude,'nominatim');
            if ($candidate!==null) $nearby[$candidate['source_url']]=$candidate;
            usort($nearby,fn($a,$b)=>$a['distance_m']<=>$b['distance_m']);
        }
        return $values+['formatted_address'=>$this->clean($data['display_name'] ?? null), 'field_sources'=>$sources,
            'confidence'=>'needs_review','landmarks'=>array_slice(array_values($nearby),0,5),
            'provider_status'=>$providers===[]?'unavailable':implode('+',$providers),
            'provider_attempts'=>['nominatim'=>$n['status'],'photon'=>$p['status']],
            'attribution'=>GeocodingGateway::ATTRIBUTION,'requires_review'=>true];
    }

    private function landmark(array $feature,float $latitude,float $longitude,string $source='photon'): ?array
    {
        $p=is_array($feature['properties'] ?? null)?$feature['properties']:[];
        $kind=($p['osm_key'] ?? '').':'.($p['osm_value'] ?? '');
        $labels=['amenity:place_of_worship'=>'دار عبادة','amenity:school'=>'مدرسة','amenity:marketplace'=>'سوق','amenity:hospital'=>'مستشفى',
            'amenity:community_centre'=>'مركز مجتمعي / قاعة','amenity:events_venue'=>'قاعة مناسبات','shop:supermarket'=>'سوق'];
        $name=$this->clean($p['name'] ?? null);$id=$p['osm_id'] ?? null;
        $type=['N'=>'node','W'=>'way','R'=>'relation','node'=>'node','way'=>'way','relation'=>'relation'][$p['osm_type'] ?? ''] ?? null;
        $coordinates=$feature['geometry']['coordinates'] ?? null;
        if (!$name || !isset($labels[$kind]) || !$type || !is_numeric($id) || (int)$id<1 ||
            ($feature['geometry']['type'] ?? '')!=='Point' || !is_array($coordinates) || count($coordinates)<2 ||
            !is_numeric($coordinates[0]) || !is_numeric($coordinates[1])) return null;
        $lon=(float)$coordinates[0];$lat=(float)$coordinates[1];
        if (!is_finite($lat) || !is_finite($lon) || abs($lat)>90 || abs($lon)>180) return null;
        $a=sin(deg2rad($lat-$latitude)/2)**2+cos(deg2rad($latitude))*cos(deg2rad($lat))*sin(deg2rad($lon-$longitude)/2)**2;
        $distance=(int)round(6371000*2*asin(sqrt(min(1,max(0,$a)))));
        if ($distance>1000) return null;
        return ['name'=>$name,'kind'=>$labels[$kind],'distance_m'=>$distance,'distance_basis'=>'straight_line',
            'source'=>$source,'source_url'=>'https://www.openstreetmap.org/'.$type.'/'.(int)$id,'confidence'=>'mapped_feature_needs_review'];
    }

    private function first(array $data,array $keys): ?string
    {
        foreach ($keys as $key) { $value=$this->clean($data[$key] ?? null);if ($value!==null) return $value; }
        return null;
    }
    private function clean(mixed $value): ?string
    {
        if (!is_string($value)) return null;
        $value=trim(strip_tags($value));return $value===''?null:mb_substr($value,0,200);
    }
}
