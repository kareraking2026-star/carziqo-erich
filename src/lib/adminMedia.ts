import { supabase } from '@/lib/supabase';

const MEDIA_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
const MEDIA_MAX_BYTES = 5 * 1024 * 1024;

export async function uploadAdminImage(file: File, folder: string): Promise<string> {
  const extension = MEDIA_TYPES[file.type];
  if (!extension) throw new Error('Image must be a JPG, PNG or WEBP file');
  if (file.size > MEDIA_MAX_BYTES) throw new Error('Image must be 5 MB or smaller');

  const path = `${folder}/${Date.now()}-${crypto.randomUUID()}.${extension}`;
  const { error } = await supabase.storage
    .from('admin-media')
    .upload(path, file, { contentType: file.type });
  if (error) throw error;

  return supabase.storage.from('admin-media').getPublicUrl(path).data.publicUrl;
}
