from pathlib import Path
p=Path('backend-api-runtime/app/Services/SupportTaskService.php')
s=p.read_text()
old="""        foreach($properties as $property){
            $existing=$existingTasks->get((int)$property->id);
            $status=match($property->review_status){
                'approved'=>'completed','rejected_blocked'=>'rejected','returned_for_correction'=>'waiting_user',
                'under_review'=>'in_progress',
                'submitted'=>$existing?->status==='waiting_user'?'new':($property->review_assigned_to_user_id?'in_progress':'new'),
                default=>'completed',
            };
            $release=$property->review_status==='submitted'&&$existing?->status==='waiting_user';
            $submitted=$property->submitted_at?:$property->updated_at?:now();
            $assigneeId=$release?null:$property->review_assigned_to_user_id;
            $task=$this->upsertTask(
                'listing_review',$property->id,'LIST-'.$property->id,'تحقيق إعلان: '.$property->title,
                $property->user,$status,'normal',null,$assigneeId,
                $assigneeId?($assigneeNames[(int)$assigneeId]??null):null,
                in_array($status,['waiting_user','completed','rejected'],true)?null:$submitted->copy()->addHours(24),
                $property->updated_at,[
                    'review_status'=>$property->review_status,'price'=>$property->price,
                    'purpose'=>$property->purpose,'property_type'=>$property->type,
                ],$release||in_array($status,['waiting_user','completed','rejected'],true)
            );
            $existingTasks->put((int)$property->id,$task);
        }
"""
new="""        foreach($properties as $property){
            $existing=$existingTasks->get((int)$property->id);
            $existingMeta=$existing?->metadata??[];
            $returnedCycle=$existing?->status==='completed'&&($existingMeta['resolution']??null)==='returned_for_correction';
            $status=match($property->review_status){
                'approved'=>'completed','rejected_blocked'=>'rejected','returned_for_correction'=>'completed',
                'under_review'=>'in_progress',
                'submitted'=>$returnedCycle?'needs_followup':($property->review_assigned_to_user_id?'in_progress':'new'),
                default=>'completed',
            };
            $release=$property->review_status==='submitted'&&$returnedCycle;
            $closed=in_array($status,self::CLOSED_STATUSES,true);
            $submitted=$property->submitted_at?:$property->updated_at?:now();
            $assigneeId=$release?null:($property->review_assigned_to_user_id?:($closed?$existing?->assigned_to_user_id:null));
            $assigneeName=$assigneeId
                ?($existing?->assigned_to_user_id===$assigneeId?$existing?->assigned_to_name_snapshot:($assigneeNames[(int)$assigneeId]??null))
                :null;
            $resolution=match($property->review_status){
                'approved'=>'approved','rejected_blocked'=>'rejected','returned_for_correction'=>'returned_for_correction',default=>null,
            };
            $task=$this->upsertTask(
                'listing_review',$property->id,'LIST-'.$property->id,'تحقق نشر إعلان: '.$property->title,
                $property->user,$status,'normal',null,$assigneeId,$assigneeName,
                $closed?null:$submitted->copy()->addHours(24),
                $property->updated_at,[
                    'review_status'=>$property->review_status,'resolution'=>$resolution,
                    'review_reason'=>$property->last_review_reason,'price'=>$property->price,
                    'purpose'=>$property->purpose,'property_type'=>$property->type,
                ],$release||$closed
            );
            $existingTasks->put((int)$property->id,$task);
        }
"""
if old not in s: raise SystemExit('syncListings block not found')
p.write_text(s.replace(old,new,1))
print('aligned support listing repair path')
