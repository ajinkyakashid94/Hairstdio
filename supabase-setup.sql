create table if not exists public.bookings (
  id bigint generated always as identity primary key,
  customer_name text not null,
  mobile text not null,
  service text not null,
  price integer not null,
  appointment_date date not null,
  appointment_time text not null,
  created_at timestamptz not null default now(),
  constraint bookings_customer_name_length check (char_length(trim(customer_name)) between 2 and 100),
  constraint bookings_mobile_format check (mobile ~ '^[6-9][0-9]{9}$'),
  constraint bookings_service_price check (
    (service = 'Hair Cutting' and price = 70) or
    (service = 'Beard Trimming (Dadhi)' and price = 50) or
    (service = 'Hair Cutting + Beard Trimming' and price = 150) or
    (service = 'Hair Dye' and price = 70) or
    (service = 'Massage' and price = 70) or
    (service = 'Face Mask' and price = 100)
  ),
  constraint bookings_unique_appointment unique (appointment_date, appointment_time)
);

alter table public.bookings enable row level security;
revoke all on table public.bookings from public, anon, authenticated;
grant usage on schema public to anon;

create or replace function public.booking_availability(selected_date date)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object('appointment_time', b.appointment_time)),
    '[]'::jsonb
  )
  from public.bookings as b
  where b.appointment_date = selected_date;
$$;

create or replace function public.create_booking(
  customer_name text,
  mobile text,
  selected_service text,
  selected_date date,
  selected_time text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  service_price integer;
begin
  if char_length(trim(customer_name)) not between 2 and 100 then
    raise exception 'Enter a valid customer name.';
  end if;

  if mobile !~ '^[6-9][0-9]{9}$' then
    raise exception 'Enter a valid 10-digit mobile number.';
  end if;

  service_price := case selected_service
    when 'Hair Cutting' then 70
    when 'Beard Trimming (Dadhi)' then 50
    when 'Hair Cutting + Beard Trimming' then 150
    when 'Hair Dye' then 70
    when 'Massage' then 70
    when 'Face Mask' then 100
    else null
  end;
  if service_price is null then
    raise exception 'Choose a valid service.';
  end if;

  if selected_date < current_date then
    raise exception 'Choose today or a future date.';
  end if;

  if not exists (
    select 1
    from generate_series(0, 20) as slot(minute_offset)
    where to_char(time '09:00' + slot.minute_offset * interval '30 minutes', 'HH12:MI AM') = selected_time
  ) then
    raise exception 'Choose a valid appointment time.';
  end if;

  insert into public.bookings (
    customer_name, mobile, service, price, appointment_date, appointment_time
  )
  values (
    trim(customer_name), mobile, selected_service, service_price, selected_date, selected_time
  );
end;
$$;

revoke all on function public.booking_availability(date) from public, anon, authenticated;
revoke all on function public.create_booking(text, text, text, date, text) from public, anon, authenticated;
grant execute on function public.booking_availability(date) to anon;
grant execute on function public.create_booking(text, text, text, date, text) to anon;

notify pgrst, 'reload schema';
