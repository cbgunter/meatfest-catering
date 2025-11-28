(function(){
  const cfg = (window.MEATFEST_CONFIG||{});
  const apiBaseUrl = (cfg.apiBaseUrl||'').replace(/\/$/,'');

  function setStatus(el, type, msg){
    if(!el) return;
    el.hidden = !msg;
    el.className = 'notice ' + (type||'');
    el.textContent = msg||'';
  }

  async function submitForm(form, kind){
    const status = form.querySelector('[data-status]');
    const submitBtn = form.querySelector('button[type="submit"]');
    const fd = new FormData(form);

    const payload = {
      type: kind,
      name: fd.get('name')||'',
      email: fd.get('email')||'',
      phone: fd.get('phone')||'',
      eventDate: fd.get('eventDate')||'',
      eventType: fd.get('eventType')||'',
      headcount: fd.get('headcount')||'',
      message: fd.get('message')||''
    };

    if(!apiBaseUrl){
      setStatus(status,'error','Form backend not configured yet. See README to connect forms.');
      return;
    }

    if(!payload.name || !payload.email){
      setStatus(status,'error','Please provide your name and email.');
      return;
    }

    try{
      setStatus(status,'', 'Sending...');
      submitBtn.disabled = true;
      const res = await fetch(apiBaseUrl + '/submit',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify(payload)
      });
      const data = await res.json().catch(()=>({}));
      if(!res.ok){
        throw new Error(data.message || ('Request failed with ' + res.status));
      }
      form.reset();
      setStatus(status,'success','Thanks! We received your request and will reach out soon.');
    }catch(err){
      setStatus(status,'error', err.message || 'Something went wrong. Please try again.');
    }finally{
      submitBtn.disabled = false;
    }
  }

  function bindForm(id, kind){
    const form = document.getElementById(id);
    if(!form) return;
    const status = document.createElement('div');
    status.setAttribute('data-status','');
    status.className = 'notice';
    status.hidden = true;
    form.prepend(status);
    form.addEventListener('submit', (e)=>{
      e.preventDefault();
      submitForm(form, kind);
    });
  }

  document.addEventListener('DOMContentLoaded', function(){
    bindForm('request-form','request');
    bindForm('contact-form','contact');
  });
})();
