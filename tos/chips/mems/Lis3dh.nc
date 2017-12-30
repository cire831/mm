interface Lis3dh {
  command uint8_t whoAmI();
  command void    config1Hz();
  command void    config100Hz();
  command bool    xyzDataAvail();
  command uint8_t fifo_count();
  command bool    is_fifo_empty();
  command bool    is_fifo_overrun();
  command bool    is_fifo_over_thresh();
  command void    readSample(uint8_t *buf, uint8_t bufLen);
}
