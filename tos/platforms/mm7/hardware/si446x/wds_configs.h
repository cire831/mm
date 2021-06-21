
/*
 * code auto-generated by wds_prep.py
*/


#ifndef __WDS_CONFIG_H__
#define __WDS_CONFIG_H__


typedef struct {
    uint32_t        sig;
    uint32_t        xtal_freq;
    uint32_t        symb_sec;
    uint32_t        freq_dev;
    uint32_t        fhst;
    uint32_t        rxbw;
} wds_config_ids_t;



int wds_set_default(int level);
uint8_t const* const* wds_config_list();
uint8_t const*              wds_config_select(uint8_t *cname);
uint8_t const*        wds_default_name();
wds_config_ids_t const* wds_default_ids();

#endif /* __WDS_CONFIG_H__ */