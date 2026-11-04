<?php

namespace App\Services;

class AndroidAppLinkAssociation
{
    public function statements(): array
    {
        $package=config('app_links.android.package_name');
        $fingerprints=config('app_links.android.sha256_cert_fingerprints',[]);
        if (!is_string($package) || !preg_match('/^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)+$/D',$package)
            || !is_array($fingerprints) || $fingerprints===[] || count($fingerprints)>5) return [];
        foreach ($fingerprints as $fingerprint) {
            if (!is_string($fingerprint) || !preg_match('/^(?:[A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$/D',$fingerprint)) return [];
        }
        return [['relation'=>['delegate_permission/common.handle_all_urls'], 'target'=>[
            'namespace'=>'android_app','package_name'=>$package,
            'sha256_cert_fingerprints'=>array_values(array_unique(array_map('strtoupper',$fingerprints))),
        ]]];
    }
}
