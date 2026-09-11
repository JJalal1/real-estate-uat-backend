from pathlib import Path
p=Path('backend-api-runtime/tests/Feature/UatAdminSupportWorkspaceApiTest.php')
s=p.read_text()
old="""        [$agent]=$this->user('workspace-agent2@example.test','+967733330006',['support_agent']);
"""
new="""        [$agent,$agentHeaders]=$this->user('workspace-agent2@example.test','+967733330006',['support_agent']);
"""
if old not in s: raise SystemExit('agent fixture pattern missing')
s=s.replace(old,new,1)
old="""        $this->withHeaders($managerHeaders)->patchJson('/api/admin/support/cases/'.$caseId.'/status',['status'=>'resolved'])->assertOk();
        $this->withHeaders($managerHeaders)->postJson('/api/admin/support/cases/'.$caseId.'/reopen',['reason'=>'الحالة تحتاج متابعة إضافية.'])
"""
new="""        // The manager owns distribution, not the normal end-user decision path.
        $this->withHeaders($managerHeaders)->patchJson('/api/admin/support/cases/'.$caseId.'/status',['status'=>'resolved'])->assertStatus(409);
        $this->withHeaders($agentHeaders)->patchJson('/api/admin/support/cases/'.$caseId.'/status',['status'=>'resolved'])->assertOk();
        $this->withHeaders($managerHeaders)->postJson('/api/admin/support/cases/'.$caseId.'/reopen',['reason'=>'الحالة تحتاج متابعة إضافية.'])
"""
if old not in s: raise SystemExit('manager resolution pattern missing')
s=s.replace(old,new,1)
p.write_text(s)
print('legacy support regression aligned')
