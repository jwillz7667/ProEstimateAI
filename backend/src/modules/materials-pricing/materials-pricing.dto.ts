import { HomeDepotProduct } from '../../lib/home-depot';

export interface MaterialPricingDto {
  product_id: string;
  title: string;
  brand: string;
  price: number | null;
  price_was: number | null;
  savings: string | null;
  percentage_off: number | null;
  rating: number | null;
  reviews: number | null;
  model_number: string | null;
  link: string;
  thumbnail: string | null;
  delivery_free: boolean;
  in_store_pickup: boolean;
  badges: string[];
}

export interface MaterialSearchResultDto {
  products: MaterialPricingDto[];
  total_results: number;
  store_name: string | null;
  query: string;
}

export interface ProjectMaterialsResultDto {
  categories: Record<string, MaterialPricingDto[]>;
  project_type: string;
  zip_code: string | null;
}

export function toMaterialPricingDto(product: HomeDepotProduct): MaterialPricingDto {
  return {
    product_id: product.product_id,
    title: product.title,
    brand: product.brand,
    price: product.price,
    price_was: product.price_was,
    savings: product.price_saving,
    percentage_off: product.percentage_off,
    rating: product.rating,
    reviews: product.reviews,
    model_number: product.model_number,
    link: product.link,
    thumbnail: product.thumbnails?.[0] ?? null,
    delivery_free: product.delivery?.free ?? false,
    in_store_pickup: product.pickup?.free ?? false,
    badges: product.badges ?? [],
  };
}
