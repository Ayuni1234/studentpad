-- Index foreign keys used by row policies, chat membership, and listing ownership.
create index chats_created_by_idx on public.chats (created_by);
create index chats_participant_one_idx on public.chats (participant_one_id);
create index chats_participant_two_idx on public.chats (participant_two_id);
create index listings_owner_idx on public.listings (owner_id);
create index messages_sender_idx on public.messages (sender_id);
